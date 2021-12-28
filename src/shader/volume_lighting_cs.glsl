// ------------------------------------------------------------------
// DEFINES ----------------------------------------------------------
// ------------------------------------------------------------------

#define LOCAL_SIZE_X 8
#define LOCAL_SIZE_Y 8
#define LOCAL_SIZE_Z 1
#define VOXEL_GRID_SIZE_X 160
#define VOXEL_GRID_SIZE_Y 90
#define VOXEL_GRID_SIZE_Z 128
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

uniform sampler2D s_ShadowMap;
uniform vec3      u_LightDirection;
uniform vec3      u_LightColor;
uniform mat4      u_LightViewProj;
uniform float     u_Bias;
uniform vec3      u_CameraPosition;
uniform mat4      u_InvViewProj;
uniform float     u_PhaseG;
uniform float     u_Density;
uniform float     u_ScatteringCoefficient;
uniform float     u_AbsorptionCoefficient;
uniform float     u_Near;
uniform float     u_Far;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

float sample_shadow_map(vec2 coord, float z)
{
    // get closest depth value from light's perspective (using [0,1] range fragPosLight as coords)
    float closest_depth = texture(s_ShadowMap, proj_coords).r;
    // get depth of current fragment from light's perspective
    float current_depth = z;
    // check whether current frag pos is in shadow
    float bias   = u_Bias;
    return current_depth - bias > closest_depth ? 1.0 : 0.0;
}

// ------------------------------------------------------------------

float visibility(vec3 p)
{
    // Transform frag position into Light-space.
    vec4 light_space_pos = u_LightViewProj * vec4(p, 1.0);

    // Perspective divide
    vec3 proj_coords = light_space_pos.xyz / light_space_pos.w;

    // Transform to [0,1] range
    proj_coords = proj_coords * 0.5 + 0.5;

    return 1.0 - sample_shadow_map(proj_coords.xy, proj_coords.z);
}

// ------------------------------------------------------------------

vec3 voxel_world_position(ivec3 coord)
{
    // Create texture coordinate 
    vec3 tex_coord = vec3(float(coord.x - 1) / VOXEL_GRID_SIZE_X,  
                          float(coord.y - 1) / VOXEL_GRID_SIZE_Y,
                          float(coord.z - 1) / VOXEL_GRID_SIZE_Z);

    // Create NDC coordinate (OpenGL Z range is -1 to +1)
    vec3 ndc_coord = 2.0f * tex_coord - vec3(1.0f);

    // Transform back into world position.
    vec4 world_pos = u_InvViewProj * vec4(ndc_pos, 1.0f);

    // Undo projection.
    world_pos = world_pos / world_pos.w;

    return world_pos.xyz;
}

// ------------------------------------------------------------------

// Henyey-Greenstein
float phase_function(vec3 Wo, vec3 Wi, float g)
{
    float cos_theta = dot(Wo, Wi);
    float denom = 1.0f + g * g + 2.0f * g * cos_theta;
    return (1.0f / (4.0f * M_PI)) * (1.0f - g * g) / (denom * sqrt(denom));
}

// ------------------------------------------------------------------

float z_slice_thickness(int z) 
{
    //return 1.0f; //linear depth
    return exp(-float(VOXEL_GRID_SIZE_Z - z - 1) / float(VOXEL_GRID_SIZE_Z));
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);

    if (all(lessThan(coord, ivec3(VOXEL_GRID_SIZE_X, VOXEL_GRID_SIZE_Y, VOXEL_GRID_SIZE_Z))))
    {
        // Get the world position of the current voxel.
        vec3 world_pos = voxel_world_position(coord);

        // Get the view direction from the current voxel.
        vec3 Wo = normalize(u_CameraPosition - world_pos);

        // Density and coefficient estimation.
        float density = u_Density; // TODO: Add noise
        float thickness = z_slice_thickness(coord.z);
        float absorption = u_AbsorptionCoefficient * density * thickness;
        float scattering = u_ScatteringCoefficient * density * thickness;

        // Perform lighting.
        vec3 lighting = vec3(0.0f);

        float visibility_value = visibility(world_pos);

        if (visibility_value > EPSILON)
            lighting = visibility_value * u_LightColor * phase_function(Wo, -u_LightDirection, u_PhaseG);
        
        // RGB = Amount of in-scattered light, A = Extinction coefficient.
        vec4 color_and_coef = vec4(lighting * scattering, absorption + scattering);

        // Write out lighting.
        imageStore(i_VoxelGrid, coord, color_and_coef);
    }
}

// ------------------------------------------------------------------