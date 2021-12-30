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
    ivec3 coord = ivec3(gl_GlobalInvocationID.xy, 0);

    vec4 current_slice = texelFetch(s_VoxelGrid, coord, 0);
    write_final_scattering(coord, current_slice);

    // Accumulate scattering
    for (int i = 1; i < VOXEL_GRID_SIZE_Z; i++)
    {
        coord.z = i;

        vec4 next_slice = texelFetch(s_VoxelGrid, coord, 0);

        current_slice = accumulate_scattering(current_slice, next_slice);

        write_final_scattering(coord, current_slice);
    }
}

// ------------------------------------------------------------------