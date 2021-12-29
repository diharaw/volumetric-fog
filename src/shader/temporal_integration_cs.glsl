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
    ivec4 width_height;
};

uniform sampler3D s_Current;
uniform sampler3D s_History;
uniform bool u_Accumulation;

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);

    if (all(lessThan(coord, ivec3(VOXEL_GRID_SIZE_X, VOXEL_GRID_SIZE_Y, VOXEL_GRID_SIZE_Z))))
    {
        // Get the world position of the current voxel.
        vec3 world_pos = id_to_world(coord, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, inv_view_proj);

        // Get the UV for the current voxel
        vec3 current_uv = world_to_uv(world_pos, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, view_proj);

        // Fetch current sample
        vec4 current = textureLod(s_Current, current_uv, 0.0f);

        vec4 result = vec4(0.0f);

        if (u_Accumulation)
        { 
            // Find the history UV
            vec3 history_uv = world_to_uv(world_pos, bias_near_far_pow.y, bias_near_far_pow.z, bias_near_far_pow.w, prev_view_proj);

            // If history UV is outside the frustum, skip history
            if (any(lessThan(history_uv, vec3(0.0f))) || any(greaterThan(history_uv, vec3(1.0f))))
                result = current;
            else 
            {
                // Fetch history sample
                vec4 history = textureLod(s_History, history_uv, 0.0f);

                result = mix(history, current, 0.05f);
            }
        }
        else 
            result = current;

        // Write out results.
        imageStore(i_VoxelGrid, coord, result);
    }
}

// ------------------------------------------------------------------