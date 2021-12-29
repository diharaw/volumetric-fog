#define VOXEL_GRID_SIZE_X 160
#define VOXEL_GRID_SIZE_Y 90
#define VOXEL_GRID_SIZE_Z 128

// ------------------------------------------------------------------

float exp_01_to_linear_01_depth(float z, float n, float f)
{
    float z_buffer_params_y = f / n;
    float z_buffer_params_x = 1.0f - z_buffer_params_y;

    return 1.0f / (z_buffer_params_x * z + z_buffer_params_y);
}

// ------------------------------------------------------------------

float linear_01_to_exp_01_depth(float z, float n, float f)
{
    float z_buffer_params_y = f / n;
    float z_buffer_params_x = 1.0f - z_buffer_params_y;

    return (1.0f / z - z_buffer_params_y) / z_buffer_params_x;
}

// ------------------------------------------------------------------

vec3 world_to_ndc(vec3 world_pos, mat4 vp)
{
    vec4 p = vp * vec4(world_pos, 1.0f);
        
    if (p.w > 0.0f)
    {
        p.x /= p.w;
        p.y /= p.w;
        p.z /= p.w;
    }
    
    return p.xyz;
}

// ------------------------------------------------------------------

vec3 ndc_to_uv(vec3 ndc, float n, float f, float depth_power)
{
    vec3 uv;
        
    uv.x = ndc.x * 0.5f + 0.5f;
    uv.y = ndc.y * 0.5f + 0.5f;
    uv.z = exp_01_to_linear_01_depth(ndc.z * 0.5f + 0.5f, n, f);
    uv.z = pow(uv.z, 1.0f / depth_power);        

    return uv;
}

// ------------------------------------------------------------------
  
vec3 world_to_uv(vec3 world_pos, float n, float f, float depth_power, mat4 vp)
{
    vec3 ndc = world_to_ndc(world_pos, vp);
    return ndc_to_uv(ndc, n, f, depth_power);
}

// ------------------------------------------------------------------
  
vec3 uv_to_ndc(vec3 uv, float n, float f, float depth_power)
{
    vec3 ndc;
        
    ndc.x = 2.0f * uv.x - 1.0f;
    ndc.y = 2.0f * uv.y - 1.0f;
    ndc.z = pow(uv.z, depth_power);
    ndc.z = 2.0f * linear_01_to_exp_01_depth(ndc.z, n, f) - 1.0f;
        
    return ndc;
}
    
// ------------------------------------------------------------------

vec3 ndc_to_world(vec3 ndc, mat4 inv_vp)
{
    vec4 p = inv_vp * vec4(ndc, 1.0f);
        
    p.x /= p.w;
    p.y /= p.w;
    p.z /= p.w;
        
    return p.xyz;
}

// ------------------------------------------------------------------

vec3 id_to_uv(ivec3 id)
{
    return vec3((float(id.x) + 0.5f) / float(VOXEL_GRID_SIZE_X),
                (float(id.y) + 0.5f) / float(VOXEL_GRID_SIZE_Y),
                (float(id.z) + 0.5f) / float(VOXEL_GRID_SIZE_Z));
}

// ------------------------------------------------------------------

vec3 id_to_uv_with_jitter(ivec3 id, float jitter)
{
    return vec3((float(id.x) + 0.5f) / float(VOXEL_GRID_SIZE_X),
                (float(id.y) + 0.5f) / float(VOXEL_GRID_SIZE_Y),
                (float(id.z) + jitter) / float(VOXEL_GRID_SIZE_Z));
}

// ------------------------------------------------------------------

vec3 id_to_world(ivec3 id, float n, float f, float depth_power, mat4 inv_vp)
{
    vec3 uv = id_to_uv(id);
    vec3 ndc = uv_to_ndc(uv, n, f, depth_power);
    return ndc_to_world(ndc, inv_vp);
}

// ------------------------------------------------------------------

vec3 id_to_world_with_jitter(ivec3 id, float jitter, float n, float f, float depth_power, mat4 inv_vp)
{
    vec3 uv = id_to_uv_with_jitter(id, jitter);
    vec3 ndc = uv_to_ndc(uv, n, f, depth_power);
    return ndc_to_world(ndc, inv_vp);
}

// ------------------------------------------------------------------