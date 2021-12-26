#extension GL_ARB_bindless_texture : require

// ------------------------------------------------------------------
// DEFINES ----------------------------------------------------------
// ------------------------------------------------------------------

#define NUM_INSTANCES 16
#define NUM_SDFS 16
#define INFINITY 100000.0f

// ------------------------------------------------------------------
// OUTPUT VARIABLES  ------------------------------------------------
// ------------------------------------------------------------------

out vec3 FS_OUT_Color;

// ------------------------------------------------------------------
// INPUT VARIABLES  -------------------------------------------------
// ------------------------------------------------------------------

in vec3 FS_IN_WorldPos;
in vec3 FS_IN_Normal;
in vec2 FS_IN_UV;
in vec4 FS_IN_NDCFragPos;

// ------------------------------------------------------------------
// STRUCTURES -------------------------------------------------------
// ------------------------------------------------------------------

struct Instance
{
    mat4  inverse_transform;
    vec4  half_extents;
    vec4  os_center;
    vec4  ws_center;
    vec4  ws_axis[3];
    ivec4 sdf_idx;
};

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

layout(std140, binding = 0) uniform GlobalUniforms
{
    mat4 view_proj;
    vec4 cam_pos;
    int  num_instances;
};

layout(std140, binding = 1) uniform Instances
{
    Instance instances[NUM_INSTANCES];
};

layout(std140, binding = 2) uniform SDFTextures
{
    sampler3D sdf[NUM_SDFS];
};

uniform vec3  u_Color;
uniform bool  u_SDFSoftShadows;
uniform float u_SDFTMin;
uniform float u_SDFTMax;
uniform float u_SDFSoftShadowsK;
uniform float u_AOStepSize;
uniform float u_AOStrength;
uniform int   u_AONumSteps;
uniform bool  u_AO;
uniform vec3  u_LightPos;
uniform vec3  u_LightDirection;
uniform float u_LightInnerCutoff;
uniform float u_LightOuterCutoff;
uniform float u_LightRange;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

vec3 transform_point(vec3 ws_p, mat4 t)
{
    return vec3(t * vec4(ws_p, 1.0f));
}

// ------------------------------------------------------------------

float sample_sdf(in vec3 os_p, in Instance instance)
{
    vec3 remapped_p = os_p - (instance.os_center.xyz - instance.half_extents.xyz);
    vec3 box_size   = instance.half_extents.xyz * 2.0f;

    vec3 uvw = (remapped_p / box_size);
    return textureLod(sdf[instance.sdf_idx.x], uvw, 0.0f).r;
}

// ------------------------------------------------------------------

bool inside_obb(in vec3 os_p, in Instance instance)
{
    vec3 min_extents = instance.os_center.xyz - instance.half_extents.xyz;
    vec3 max_extents = instance.os_center.xyz + instance.half_extents.xyz;

    return all(greaterThanEqual(os_p, min_extents)) && all(lessThanEqual(os_p, max_extents));
}

// ------------------------------------------------------------------

vec3 calculate_normal(in vec3 os_p, in Instance instance)
{
    const float eps = 0.0001f;
    const vec2  h   = vec2(eps, 0.0f);
    return normalize(vec3(sample_sdf(os_p + h.xyy, instance) - sample_sdf(os_p - h.xyy, instance),
                          sample_sdf(os_p + h.yxy, instance) - sample_sdf(os_p - h.yxy, instance),
                          sample_sdf(os_p + h.yyx, instance) - sample_sdf(os_p - h.yyx, instance)));
}

// ------------------------------------------------------------------

vec3 find_closest_point_on_obb(in vec3 ws_p, in Instance instance)
{
    vec3 c = instance.ws_center.xyz;

    vec3 d = ws_p - c;
    vec3 q = c;

    for (int i = 0; i < 3; i++)
    {
        float dist = dot(d, instance.ws_axis[i].xyz);

        if (dist > instance.half_extents[i]) dist = instance.half_extents[i];
        if (dist < -instance.half_extents[i]) dist = -instance.half_extents[i];

        q += dist * instance.ws_axis[i].xyz;
    }

    return q;
}

// ------------------------------------------------------------------

vec3 find_closest_point_on_mesh(in vec3 ws_p, in Instance instance)
{
    vec3 os_p = transform_point(ws_p, instance.inverse_transform);

    float t = sample_sdf(os_p, instance);

    return ws_p - calculate_normal(os_p, instance) * t;
}

// ------------------------------------------------------------------

float evaluate_mesh_sdf(in vec3 ws_p, in Instance instance)
{
    vec3 os_p = transform_point(ws_p, instance.inverse_transform);

    if (inside_obb(os_p, instance))
        return sample_sdf(os_p, instance);
    else
    {
#if defined(USE_ACCURATE_DISTANCE)
        vec3 point_on_volume = find_closest_point_on_obb(ws_p, instance);
        vec3 point_on_mesh   = find_closest_point_on_mesh(point_on_volume, instance);

        float h = length(point_on_mesh - ws_p);

        return h;
#else
        vec3 point_on_volume = find_closest_point_on_obb(ws_p, instance);
        return length(point_on_volume - ws_p) + sample_sdf(transform_point(point_on_volume, instance.inverse_transform), instance);
#endif
    }
}

// ------------------------------------------------------------------

float evaluate_scene_sdf(vec3 ws_p)
{
    float dist_to_box = INFINITY;

    for (int i = 0; i < num_instances; i++)
    {
        float h = evaluate_mesh_sdf(ws_p, instances[i]);

        if (h < dist_to_box)
            dist_to_box = h;
    }

    return dist_to_box;
}

// ------------------------------------------------------------------

float shadow_ray_march(vec3 ro, vec3 rd, float k)
{
    float res = 1.0;

    for (float t = u_SDFTMin; t < u_SDFTMax;)
    {
        vec3 p = ro + rd * t;

        float h = evaluate_scene_sdf(p);

        if (h < 0.001f)
            return 0.0f;

        if (u_SDFSoftShadows)
            res = min(res, k * h / t);

        t += h;
    }

    return res;
}

// ------------------------------------------------------------------

// https://www.alanzucconi.com/2016/07/01/ambient-occlusion/
float ambient_occlusion(vec3 pos, vec3 normal, int num_steps, float step_size)
{
    float sum     = 0;
    float max_sum = 0;
    for (int i = 0; i < num_steps; i++)
    {
        vec3 p = pos + normal * (i + 1) * step_size;
        sum += 1. / pow(2., i) * evaluate_scene_sdf(p);
        max_sum += 1. / pow(2., i) * (i + 1) * step_size;
    }
    return min(sum / max_sum, 1.0f);
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    vec3 albedo = u_Color;
    vec3 N      = normalize(FS_IN_Normal);
    vec3 L      = normalize(u_LightPos - FS_IN_WorldPos); // FragPos -> LightPos vector

    float theta       = dot(L, normalize(-u_LightDirection));
    float distance    = length(FS_IN_WorldPos - u_LightPos);
    float epsilon     = u_LightInnerCutoff - u_LightOuterCutoff;
    float attenuation = smoothstep(u_LightRange, 0, distance) * clamp((theta - u_LightOuterCutoff) / epsilon, 0.0, 1.0);

    float shadow = shadow_ray_march(FS_IN_WorldPos, L, u_SDFSoftShadowsK) * attenuation;
    float ao     = u_AO ? ambient_occlusion(FS_IN_WorldPos, FS_IN_Normal, u_AONumSteps, u_AOStepSize) : 1.0f;

    FS_OUT_Color = albedo * clamp(dot(N, L), 0.0, 1.0) * shadow + albedo * u_AOStrength * ao;
}

// ------------------------------------------------------------------