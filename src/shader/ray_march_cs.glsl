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

// https://github.com/Unity-Technologies/VolumetricLighting/blob/master/Assets/VolumetricFog/Shaders/Scatter.compute
vec4 accumulate(vec3 accum_scattering, float accum_transmittance, vec3 slice_scattering, float slice_density)
{
    const float slice_transmittance = exp(-slice_density / VOXEL_GRID_SIZE_Z);
    //const float slice_transmittance = exp(-slice_density);

    vec3 slice_scattering_integral = slice_scattering * (1.0 - slice_transmittance) / slice_density;

    accum_scattering += slice_scattering_integral * accum_transmittance;
    accum_transmittance *= slice_transmittance;

    return vec4(accum_scattering, accum_transmittance);
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    vec4 accum_scattering_transmittance = vec4(0.0f, 0.0f, 0.0f, 1.0f);

    // Accumulate scattering
    for (int z = 0; z < VOXEL_GRID_SIZE_Z; z++)
    {
        ivec3 coord = ivec3(gl_GlobalInvocationID.xy, z);

        vec4 slice_scattering_density = texelFetch(s_VoxelGrid, coord, 0);

        accum_scattering_transmittance = accumulate(accum_scattering_transmittance.rgb, 
                                                    accum_scattering_transmittance.a,
                                                    slice_scattering_density.rgb,
                                                    slice_scattering_density.a);

        imageStore(i_VoxelGrid, coord, accum_scattering_transmittance);
    }
}

// ------------------------------------------------------------------