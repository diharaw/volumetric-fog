#include <common.glsl>

// ------------------------------------------------------------------
// DEFINES ----------------------------------------------------------
// ------------------------------------------------------------------

#define LOCAL_SIZE_X VOXEL_GRID_SIZE_Z
#define LOCAL_SIZE_Y 1
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
// SHARED -----------------------------------------------------------
// ------------------------------------------------------------------

shared vec4 g_cached_scattering[VOXEL_GRID_SIZE_Z];

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

uniform sampler3D s_VoxelGrid;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

vec4 accumulate_scattering(vec4 front, vec4 back)
{
    // Accumulate the incoming light by attenuating it using the transmittance.
    vec3 light = front.rgb + clamp(exp(-front.a), 0.0f, 1.0f) * back.rgb;

    return vec4(light, front.a + back.a);
}

// ------------------------------------------------------------------

void write_final_scattering(ivec3 coord, vec4 value)
{
    float transmittance = exp(-value.a);
    imageStore(i_VoxelGrid, coord, vec4(value.rgb, transmittance));
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    ivec3 coord = ivec3(gl_WorkGroupID.x, gl_WorkGroupID.y, gl_LocalInvocationIndex);

    // Populate cache
    g_cached_scattering[gl_LocalInvocationIndex] = texelFetch(s_VoxelGrid, coord, 0);

    barrier();

    // Accumulate scattering
    if (gl_LocalInvocationIndex == 0)
    {
        for (int i = 1; i < VOXEL_GRID_SIZE_Z; i++)
            g_cached_scattering[i] = accumulate_scattering(g_cached_scattering[i - 1], g_cached_scattering[i]);
    }

    barrier();

    // Write out final scattering.
    write_final_scattering(coord, g_cached_scattering[gl_LocalInvocationIndex]);
}

// ------------------------------------------------------------------