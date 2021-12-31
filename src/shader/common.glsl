#define VOXEL_GRID_SIZE_X 160
#define VOXEL_GRID_SIZE_Y 90
#define VOXEL_GRID_SIZE_Z 128
#define BLUE_NOISE_TEXTURE_SIZE 128

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

    // Exponential View-Z
    vec2 params = vec2(float(VOXEL_GRID_SIZE_Z) / log2(f / n), -(float(VOXEL_GRID_SIZE_Z) * log2(n) / log2(f / n)));

    float view_z = uv.z * f;
    uv.z = (max(log2(view_z) * params.x + params.y, 0.0f)) / VOXEL_GRID_SIZE_Z;
     
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
    ndc.z = 2.0f * linear_01_to_exp_01_depth(uv.z, n, f) - 1.0f;
        
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

vec3 id_to_uv(ivec3 id, float n, float f)
{
    // Exponential View-Z
    float view_z = n * pow(f / n, (float(id.z) + 0.5f) / float(VOXEL_GRID_SIZE_Z));

    return vec3((float(id.x) + 0.5f) / float(VOXEL_GRID_SIZE_X),
                (float(id.y) + 0.5f) / float(VOXEL_GRID_SIZE_Y),
                view_z / f);
}

// ------------------------------------------------------------------

vec3 id_to_uv_with_jitter(ivec3 id, float n, float f, float jitter)
{
    // Exponential View-Z
    float view_z = n * pow(f / n, (float(id.z) + 0.5f + jitter) / float(VOXEL_GRID_SIZE_Z));

    return vec3((float(id.x) + 0.5f) / float(VOXEL_GRID_SIZE_X),
                (float(id.y) + 0.5f) / float(VOXEL_GRID_SIZE_Y),
                view_z / f);
}

// ------------------------------------------------------------------

vec3 id_to_world(ivec3 id, float n, float f, float depth_power, mat4 inv_vp)
{
    vec3 uv = id_to_uv(id, n, f);
    vec3 ndc = uv_to_ndc(uv, n, f, depth_power);
    return ndc_to_world(ndc, inv_vp);
}

// ------------------------------------------------------------------

vec3 id_to_world_with_jitter(ivec3 id, float jitter, float n, float f, float depth_power, mat4 inv_vp)
{
    vec3 uv = id_to_uv_with_jitter(id, n, f, jitter);
    vec3 ndc = uv_to_ndc(uv, n, f, depth_power);
    return ndc_to_world(ndc, inv_vp);
}

// ------------------------------------------------------------------

// https://gist.github.com/Fewes/59d2c831672040452aa77da6eaab2234
vec4 textureTricubic(sampler3D tex, vec3 coord)
{
	// Shift the coordinate from [0,1] to [-0.5, texture_size-0.5]
    vec3 texture_size = vec3(textureSize(tex, 0));
	vec3 coord_grid = coord * texture_size - 0.5;
	vec3 index = floor(coord_grid);
	vec3 fraction = coord_grid - index;
	vec3 one_frac = 1.0 - fraction;

	vec3 w0 = 1.0/6.0 * one_frac*one_frac*one_frac;
	vec3 w1 = 2.0/3.0 - 0.5 * fraction*fraction*(2.0-fraction);
	vec3 w2 = 2.0/3.0 - 0.5 * one_frac*one_frac*(2.0-one_frac);
	vec3 w3 = 1.0/6.0 * fraction*fraction*fraction;

	vec3 g0 = w0 + w1;
	vec3 g1 = w2 + w3;
	vec3 mult = 1.0 / texture_size;
	vec3 h0 = mult * ((w1 / g0) - 0.5 + index); //h0 = w1/g0 - 1, move from [-0.5, texture_size-0.5] to [0,1]
	vec3 h1 = mult * ((w3 / g1) + 1.5 + index); //h1 = w3/g1 + 1, move from [-0.5, texture_size-0.5] to [0,1]

	// Fetch the eight linear interpolations
	// Weighting and fetching is interleaved for performance and stability reasons
	vec4 tex000 = texture(tex, h0, 0.0f);
	vec4 tex100 = texture(tex, vec3(h1.x, h0.y, h0.z), 0.0f);
	tex000 = mix(tex100, tex000, g0.x); // Weigh along the x-direction

	vec4 tex010 = texture(tex, vec3(h0.x, h1.y, h0.z), 0.0f);
	vec4 tex110 = texture(tex, vec3(h1.x, h1.y, h0.z), 0.0f);
	tex010 = mix(tex110, tex010, g0.x); // Weigh along the x-direction
	tex000 = mix(tex010, tex000, g0.y); // Weigh along the y-direction

	vec4 tex001 = texture(tex, vec3(h0.x, h0.y, h1.z), 0.0f);
	vec4 tex101 = texture(tex, vec3(h1.x, h0.y, h1.z), 0.0f);
	tex001 = mix(tex101, tex001, g0.x); // Weigh along the x-direction

	vec4 tex011 = texture(tex, vec3(h0.x, h1.y, h1.z), 0.0f);
	vec4 tex111 = texture(tex, vec3(h1), 0.0f);
	tex011 = mix(tex111, tex011, g0.x); // Weigh along the x-direction
	tex001 = mix(tex011, tex001, g0.y); // Weigh along the y-direction

	return mix(tex001, tex000, g0.z); // Weigh along the z-direction
}

// ------------------------------------------------------------------