import os
from ray.serve.llm import LLMConfig, build_openai_app

# We define the config without the extra 'scaling_config' field 
# to avoid the Pydantic ValidationError.
llm_config = LLMConfig(
    model_loading_config=dict(
        model_id=os.environ.get("SERVED_MODEL_NAME", "gemma-3-1b-dolly"),
        model_source=os.environ.get("MODEL_PATH", "/mnt/checkpoints/gemma-3-1b-dolly/merged"),
    ),
    deployment_config=dict(
        autoscaling_config=dict(
            min_replicas=1,
            max_replicas=1, 
            target_ongoing_requests=8,
        ),
        max_ongoing_requests=32,
        # By providing num_cpus/num_gpus here and setting 
        # tensor_parallel_size to 1, we try to satisfy the 
        # single-node constraint.
        ray_actor_options=dict(
            num_cpus=1, 
            num_gpus=1
        ),
    ),
    engine_kwargs=dict(
        # CRITICAL: This must be 1. If it's 1, some versions 
        # of the adapter will stop trying to create extra bundles.
        tensor_parallel_size=1, 
        gpu_memory_utilization=0.80,
        max_model_len=8192,
        dtype="bfloat16",
        trust_remote_code=False,
        # This tells vLLM to use the existing Ray process 
        # rather than spawning new ones.
        enforce_eager=True, 
    ),
)

deployment = build_openai_app({"llm_configs": [llm_config]})