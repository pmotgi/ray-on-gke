"""
Distributed LoRA fine-tuning of Gemma 3 1B on databricks-dolly-15k using Ray Train.

Why Ray Train here:
  * Lets us scale from 1 GPU to N GPUs by changing num_workers — same code.
  * Handles fault tolerance and worker coordination automatically.
  * Plays nicely with the Ray Serve worker on the same cluster (shared GCS path).

Why LoRA:
  * 1B model in bf16 fits easily on a 96GB RTX PRO 6000, but LoRA is what we
    teach the customer because it's the right pattern for the 7B / 13B / 70B
    models they'll actually want to fine-tune in production.

Output:
  /mnt/checkpoints/<RUN_NAME>/lora-adapter/   # PEFT adapter
  /mnt/checkpoints/<RUN_NAME>/merged/         # full merged model (vLLM-loadable)

The /mnt/checkpoints path is a GCSFuse mount of gs://<BUCKET>/checkpoints
configured in the RayJob YAML, so writes here are visible to the serving pods.
"""
from __future__ import annotations

import os
from dataclasses import dataclass

import ray
from ray import train
from ray.train import ScalingConfig, RunConfig
from ray.train.torch import TorchTrainer

# ---- Config -----------------------------------------------------------------

@dataclass
class TrainConfig:
    base_model: str = os.environ.get("BASE_MODEL", "google/gemma-3-1b-it")
    dataset_name: str = os.environ.get("DATASET_NAME", "databricks/databricks-dolly-15k")
    run_name: str = os.environ.get("RUN_NAME", "gemma-3-1b-dolly")
    checkpoint_root: str = os.environ.get("CHECKPOINT_ROOT", "/mnt/checkpoints")

    # Training hparams — kept small so the demo finishes in ~15-20 min.
    num_train_epochs: int = int(os.environ.get("NUM_EPOCHS", "1"))
    max_seq_length: int = 1024
    per_device_batch_size: int = 4
    gradient_accumulation_steps: int = 4
    learning_rate: float = 2e-4
    max_train_samples: int = int(os.environ.get("MAX_TRAIN_SAMPLES", "2000"))

    # LoRA
    lora_r: int = 16
    lora_alpha: int = 32
    lora_dropout: float = 0.05

    # Ray scaling
    num_workers: int = int(os.environ.get("NUM_WORKERS", "1"))
    use_gpu: bool = True


# ---- Per-worker training loop ----------------------------------------------

def train_loop_per_worker(cfg_dict: dict) -> None:
    """Runs on each Ray Train worker. One worker == one GPU for this demo."""
    import torch
    from datasets import load_dataset
    from peft import LoraConfig, get_peft_model, PeftModel
    from transformers import (
        AutoModelForCausalLM,
        AutoTokenizer,
        TrainingArguments,
    )
    from trl import SFTTrainer, SFTConfig

    cfg = TrainConfig(**cfg_dict)
    rank = train.get_context().get_world_rank()
    world_size = train.get_context().get_world_size()
    print(f"[worker {rank}/{world_size}] starting on device {torch.cuda.current_device()}")

    # ---- Tokenizer + model
    tokenizer = AutoTokenizer.from_pretrained(cfg.base_model, use_fast=True)
    if tokenizer.pad_token is None:
        tokenizer.pad_token = tokenizer.eos_token

    model = AutoModelForCausalLM.from_pretrained(
        cfg.base_model,
        torch_dtype=torch.bfloat16,
        attn_implementation="eager",  # Gemma 3 prefers eager during training
        device_map={"": torch.cuda.current_device()},
    )
    model.config.use_cache = False
    model.gradient_checkpointing_enable()

    # ---- LoRA wrap
    lora = LoraConfig(
        r=cfg.lora_r,
        lora_alpha=cfg.lora_alpha,
        lora_dropout=cfg.lora_dropout,
        bias="none",
        task_type="CAUSAL_LM",
        # Standard Gemma attention proj names; LoRA on q/k/v/o is a strong default.
        target_modules=["q_proj", "k_proj", "v_proj", "o_proj"],
    )
    model = get_peft_model(model, lora)
    if rank == 0:
        model.print_trainable_parameters()

    # ---- Dataset
    ds = load_dataset(cfg.dataset_name, split="train")
    if cfg.max_train_samples and len(ds) > cfg.max_train_samples:
        ds = ds.select(range(cfg.max_train_samples))

    def to_text(ex):
        # Render dolly-15k into a Gemma 3 chat template.
        instruction = ex.get("instruction", "")
        context = ex.get("context", "") or ""
        response = ex.get("response", "")
        user = instruction + (f"\n\nContext: {context}" if context else "")
        messages = [
            {"role": "user", "content": user},
            {"role": "assistant", "content": response},
        ]
        return {"text": tokenizer.apply_chat_template(messages, tokenize=False)}

    ds = ds.map(to_text, remove_columns=ds.column_names)

    # ---- Training
    output_dir = os.path.join(cfg.checkpoint_root, cfg.run_name)
    sft_args = SFTConfig(
        output_dir=output_dir,
        num_train_epochs=cfg.num_train_epochs,
        per_device_train_batch_size=cfg.per_device_batch_size,
        gradient_accumulation_steps=cfg.gradient_accumulation_steps,
        learning_rate=cfg.learning_rate,
        bf16=True,
        gradient_checkpointing=True,
        logging_steps=10,
        save_strategy="epoch",
        save_total_limit=1,
        report_to="none",
        # Critical when launched by Ray Train: HF Trainer would otherwise try to
        # init its own torch.distributed group.
        ddp_find_unused_parameters=False,
        dataset_text_field="text",
        packing=False,
    )

    trainer = SFTTrainer(
        model=model,
        args=sft_args,
        train_dataset=ds,
        processing_class=tokenizer,
    )
    trainer.train()

    # ---- Save (rank 0 only — checkpoints go straight to GCS via GCSFuse)
    if rank == 0:
        adapter_dir = os.path.join(output_dir, "lora-adapter")
        merged_dir = os.path.join(output_dir, "merged")
        trainer.model.save_pretrained(adapter_dir)
        tokenizer.save_pretrained(adapter_dir)
        print(f"[worker 0] LoRA adapter saved to {adapter_dir}")

        # Merge LoRA into base weights so vLLM can serve a single model dir.
        # (vLLM does support runtime LoRA, but a merged checkpoint is the
        # simplest serving story for a demo.)
        print("[worker 0] Merging LoRA into base weights...")
        base = AutoModelForCausalLM.from_pretrained(
            cfg.base_model, torch_dtype=torch.bfloat16
        )
        merged = trainer.model.merge_and_unload()
        merged.save_pretrained(merged_dir, safe_serialization=True)
        tokenizer.save_pretrained(merged_dir)
        print(f"[worker 0] Merged model saved to {merged_dir}")

    train.report({"status": "done"})


# ---- Driver -----------------------------------------------------------------

def main() -> None:
    cfg = TrainConfig()
    print(f"[driver] config: {cfg}")

    ray.init(address="auto")

    trainer = TorchTrainer(
        train_loop_per_worker=train_loop_per_worker,
        train_loop_config=cfg.__dict__,
        scaling_config=ScalingConfig(
            num_workers=cfg.num_workers,
            use_gpu=cfg.use_gpu,
            resources_per_worker={"GPU": 1, "CPU": 8},
        ),
        run_config=RunConfig(
            name=cfg.run_name,
            storage_path=os.path.join(cfg.checkpoint_root, "ray-runs"),
        ),
    )
    result = trainer.fit()
    print(f"[driver] training finished: {result}")


if __name__ == "__main__":
    main()