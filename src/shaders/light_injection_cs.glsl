#include <common.glsl>

// ------------------------------------------------------------------
// DEFINES ----------------------------------------------------------
// ------------------------------------------------------------------

#define LOCAL_SIZE_X 8
#define LOCAL_SIZE_Y 8
#define LOCAL_SIZE_Z 1
#define M_PI 3.14159265359
#define EPSILON 0.0001f

// ------------------------------------------------------------------
// INPUTS -----------------------------------------------------------
// ------------------------------------------------------------------

layout(local_size_x = LOCAL_SIZE_X, local_size_y = LOCAL_SIZE_Y, local_size_z = LOCAL_SIZE_Z) in;

// ------------------------------------------------------------------
// OUTPUT -----------------------------------------------------------
// ------------------------------------------------------------------

layout(binding = 0, rgba16f) uniform writeonly image3D i_VoxelGrid;

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

layout(std140, binding = 0) uniform Uniforms
{
    mat4  view;
    mat4  projection;
    mat4  view_proj;
    mat4  prev_view_proj;
    mat4  light_view_proj;
    mat4  inv_view_proj;
    vec4  light_direction;
    vec4  light_color;
    vec4  camera_position;
    vec4  bias_near_far_pow;
    vec4  aniso_density_scattering_absorption;
    vec4  time;
    ivec4 width_height;
};

uniform sampler2DShadow s_ShadowMap;
uniform sampler2D s_BlueNoise;
uniform sampler3D s_History;

uniform bool u_Accumulation;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

float sample_shadow_map(vec2 coord, float z)
{
    float current_depth = z;
    float bias = bias_near_far_pow.x;

    return texture(s_ShadowMap, vec3(coord, current_depth - bias));
}

// ------------------------------------------------------------------

float visibility(vec3 p)
{
    // Transform frag position into Light-space.
    vec4 light_space_pos = light_view_proj * vec4(p, 1.0);

    // Perspective divide
    vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;

    // Transform to [0,1] range
    proj_coords = proj_coords * 0.5 + 0.5;

    if (any(greaterThan(proj_coords.xy, vec2(1.0f))) || any(lessThan(proj_coords.xy, vec2(0.0f))))
        return 1.0f;

    return sample_shadow_map(proj_coords.xy, proj_coords.z);
}

// ------------------------------------------------------------------

// Henyey-Greenstein
float phase_function(vec3 Wo, vec3 Wi, float g)
{
    float cos_theta = dot(Wo, Wi);
    float denom     = 1.0f + g * g + 2.0f * g * cos_theta;
    return (1.0f / (4.0f * M_PI)) * (1.0f - g * g) / max(pow(denom, 1.5f), EPSILON);
}

// ------------------------------------------------------------------

float z_slice_thickness(int z)
{
    //return 1.0f; //linear depth
    return exp(-float(VOXEL_GRID_SIZE_Z - z - 1) / float(VOXEL_GRID_SIZE_Z));
}

// ------------------------------------------------------------------

float sample_blue_noise(ivec3 coord)
{
    ivec2 noise_coord = (coord.xy + ivec2(0, 1) * coord.z * BLUE_NOISE_TEXTURE_SIZE) % BLUE_NOISE_TEXTURE_SIZE;
    return texelFetch(s_BlueNoise, noise_coord, 0).r;
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);

    if (all(lessThan(coord, ivec3(VOXEL_GRID_SIZE_X, VOXEL_GRID_SIZE_Y, VOXEL_GRID_SIZE_Z))))
    {
        // Get jitter for the current pixel, remapped to -0.5 to +0.5 range.
        float jitter = (sample_blue_noise(coord) - 0.5f) * 0.999f;

        // Get the world position of the current voxel.
        vec3 world_pos = id_to_world_with_jitter(coord, jitter, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, inv_view_proj);

        // Get the view direction from the current voxel.
        vec3 Wo = normalize(camera_position.xyz - world_pos);

        // Density and coefficient estimation.
        float thickness  = z_slice_thickness(coord.z);
        float density    = aniso_density_scattering_absorption.y;
        
        // Perform lighting.
        vec3 lighting = light_color.rgb * light_color.a;

        float visibility_value = visibility(world_pos);

        if (visibility_value > EPSILON)
            lighting += visibility_value * light_color.xyz * phase_function(Wo, -light_direction.xyz, aniso_density_scattering_absorption.x);

        // RGB = Amount of in-scattered light, A = Density.
        vec4 color_and_density = vec4(lighting * density, density);

        // Temporal accumulation
        if (u_Accumulation)
        { 
            vec3 world_pos_without_jitter = id_to_world(coord, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, inv_view_proj);                

            // Find the history UV
            vec3 history_uv = world_to_uv(world_pos_without_jitter, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, prev_view_proj);

            // If history UV is outside the frustum, skip history
            if (all(greaterThanEqual(history_uv, vec3(0.0f))) && all(lessThanEqual(history_uv, vec3(1.0f))))
            {
                // Fetch history sample
                vec4 history = textureLod(s_History, history_uv, 0.0f);

                color_and_density = mix(history, color_and_density, 0.05f);
            }
        }

        // Write out lighting.
        imageStore(i_VoxelGrid, coord, color_and_density);
    }
}

// ------------------------------------------------------------------