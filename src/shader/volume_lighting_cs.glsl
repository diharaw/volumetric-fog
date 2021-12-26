// ------------------------------------------------------------------
// DEFINES ----------------------------------------------------------
// ------------------------------------------------------------------

#define INFINITY 100000000.0f

// ------------------------------------------------------------------
// INPUTS -----------------------------------------------------------
// ------------------------------------------------------------------

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

// ------------------------------------------------------------------
// INPUT ------------------------------------------------------------
// ------------------------------------------------------------------

layout(binding = 0, r32f) uniform image3D i_SDF;

// ------------------------------------------------------------------
// STRUCTURES -------------------------------------------------------
// ------------------------------------------------------------------

struct Vertex
{
    vec4 position;
    vec4 tex_coord;
    vec4 normal;
    vec4 tangent;
    vec4 bitangent;
};

// ------------------------------------------------------------------
// UNIFORMS ---------------------------------------------------------
// ------------------------------------------------------------------

layout(std430, binding = 0) buffer Vertices
{
    Vertex vertices[];
};

layout(std430, binding = 1) buffer Indices
{
    uint indices[];
};

uniform vec3  u_GridStepSize;
uniform vec3  u_GridOrigin;
uniform uint  u_NumTriangles;
uniform ivec3 u_VolumeSize;

// ------------------------------------------------------------------
// FUNCTIONS --------------------------------------------------------
// ------------------------------------------------------------------

float dot2(in vec2 v) { return dot(v, v); }

// ------------------------------------------------------------------

float dot2(in vec3 v) { return dot(v, v); }

// ------------------------------------------------------------------

float ndot(in vec2 a, in vec2 b) { return a.x * b.x - a.y * b.y; }

// ------------------------------------------------------------------

float sdf_triangle(vec3 p, vec3 a, vec3 b, vec3 c)
{
    vec3 ba  = b - a;
    vec3 pa  = p - a;
    vec3 cb  = c - b;
    vec3 pb  = p - b;
    vec3 ac  = a - c;
    vec3 pc  = p - c;
    vec3 nor = cross(ba, ac);

    return sqrt(
        (sign(dot(cross(ba, nor), pa)) + sign(dot(cross(cb, nor), pb)) + sign(dot(cross(ac, nor), pc)) < 2.0) ?
            min(min(
                    dot2(ba * clamp(dot(ba, pa) / dot2(ba), 0.0, 1.0) - pa),
                    dot2(cb * clamp(dot(cb, pb) / dot2(cb), 0.0, 1.0) - pb)),
                dot2(ac * clamp(dot(ac, pc) / dot2(ac), 0.0, 1.0) - pc)) :
            dot(nor, pa) * dot(nor, pa) / dot2(nor));
}

// ------------------------------------------------------------------

bool is_front_facing(vec3 p, Vertex v0, Vertex v1, Vertex v2)
{
    return dot(normalize(p - v0.position.xyz), v0.normal.xyz) >= 0.0f || dot(normalize(p - v1.position.xyz), v1.normal.xyz) >= 0.0f || dot(normalize(p - v2.position.xyz), v2.normal.xyz) >= 0.0f;
}

// ------------------------------------------------------------------
// MAIN -------------------------------------------------------------
// ------------------------------------------------------------------

void main()
{
    ivec3 coord = ivec3(gl_GlobalInvocationID.xyz);

    if (all(lessThan(coord, u_VolumeSize)))
    {
        vec3 p = u_GridOrigin + u_GridStepSize * vec3(coord);

        float closest_dist = INFINITY;
        bool  front_facing = true;

        for (int i = 0; i < u_NumTriangles; i++)
        {
            Vertex v0 = vertices[indices[3 * i]];
            Vertex v1 = vertices[indices[3 * i + 1]];
            Vertex v2 = vertices[indices[3 * i + 2]];

            float h = sdf_triangle(p, v0.position.xyz, v1.position.xyz, v2.position.xyz);

            if (h < closest_dist)
            {
                closest_dist = h;
                front_facing = is_front_facing(p, v0, v1, v2);
            }
        }

        imageStore(i_SDF, coord, vec4(front_facing ? closest_dist : -closest_dist));
    }
}

// ------------------------------------------------------------------