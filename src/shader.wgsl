struct VertexOutput {
    @builtin(position) clip_position: vec4<f32>,
};

struct Properties {
    size: vec2<f32>,    // Window size
    time: f32,          // Time elapsed
    camera_yaw: f32,
    camera_pitch: f32,
    y_input_axis: f32,
    box_z_position: f32,
}

var<push_constant> push_constants: Properties;

@vertex
fn vs_main(
    @builtin(vertex_index) in_vertex_index: u32,
) -> VertexOutput {
    var out: VertexOutput;

    // Define a screen-filling quad (two triangles)
    let positions = array<vec2<f32>, 4>(
        vec2<f32>(-1.0, 1.0),   // TL vertex 0
        vec2<f32>(-1.0, -1.0),  // BL vertex 1
        vec2<f32>(1.0, -1.0),   // BR vertex 2
        vec2<f32>(1.0, 1.0),    // TR vertex 3
    );

    let indices = array<u32, 6>(
        0, 1, 2,
        0, 2, 3
    );

    let pos = positions[indices[in_vertex_index]];
    out.clip_position = vec4<f32>(pos.x, pos.y, 0.0, 1.0);

    return out;
}

struct SdfInfo {
    dist: f32,          // Distance to surface
    material_id: i32,   // ID to identify material properties
};

// Smooth minimum function for blending SDF shapes
// k controls the blending radius
fn smin(a: SdfInfo, b: SdfInfo, k: f32) -> SdfInfo {
    let h = max(k - abs(a.dist - b.dist), 0.0) / k;
    let m = 0.5 + 0.5 * (b.dist - a.dist) / max(abs(b.dist - a.dist), 0.0001);
    let d = min(a.dist, b.dist) - h * h * h * k * (1.0 / 6.0);

    // Special material ID for blended regions
    let blend_amount = h * h * h;
    let mat_id = select(
        select(b.material_id, a.material_id, a.dist < b.dist),
        -1,
        blend_amount > 0.1
    );

    return SdfInfo(d, mat_id);
}

fn sphere_sdf(p: vec3<f32>, center: vec3<f32>, radius: f32, mat_id: i32) -> SdfInfo {
    return SdfInfo(length(p - center) - radius, mat_id);
}

fn box_sdf(p: vec3<f32>, center: vec3<f32>, b: vec3<f32>, mat_id: i32) -> SdfInfo {
    let q = abs(p - center) - b;
    return SdfInfo(
        length(max(q, vec3<f32>(0.0))) + min(max(q.x, max(q.y, q.z)), 0.0),
        mat_id
    );
}

fn plane_sdf(p: vec3<f32>, n: vec3<f32>, h: f32, mat_id: i32) -> SdfInfo {
    return SdfInfo(dot(-p, n) + h, mat_id);
}

// Material IDs
const MAT_RED_SPHERE = 0;
const MAT_BLUE_SPHERE = 1;
const MAT_GREEN_BOX = 2;
const MAT_GROUND = 3;
const MAT_MIRROR_SPHERE = 4;  // Reflective material

// Material properties
struct Material {
    color: vec3<f32>,
    reflectivity: f32,
};

// Returns material properties for a given material ID
fn get_material(mat_id: i32, p: vec3<f32>) -> Material {
    var material: Material;
    material.reflectivity = 0.0;  // Default: non-reflective

    switch(mat_id) {
        case MAT_RED_SPHERE: {
            material.color = vec3<f32>(0.9, 0.1, 0.1);
        }
        case MAT_BLUE_SPHERE: {
            material.color = vec3<f32>(0.1, 0.2, 0.8);
        }
        case MAT_GREEN_BOX: {
            material.color = vec3<f32>(0.2, 0.8, 0.2);
            material.reflectivity = 0.3;  // Slightly reflective
        }
        case MAT_GROUND: {
            // Checkerboard pattern for the ground
            let checker = (floor(p.x * 0.5) + floor(p.z * 0.5)) % 2.0;
            material.color = mix(
                vec3<f32>(0.8, 0.8, 0.8),
                vec3<f32>(0.2, 0.2, 0.2),
                checker
            );
        }
        case MAT_MIRROR_SPHERE: {
            material.color = vec3<f32>(0.4, 0.4, 0.4);
            material.reflectivity = 0.9;  // Highly reflective
        }
        default: {
            material.color = vec3<f32>(1.0, 1.0, 0.0);
        }
    }

    return material;
}

// Main scene distance function - determines the distance to the nearest surface
fn map_scene(p: vec3<f32>, is_reflection: bool) -> SdfInfo {
    let time = push_constants.time;

    let sphere1_pos = vec3<f32>(
        sin(time) * 1.0,
        cos(time) * 1.0,
        2.0
    );
    let sphere1 = sphere_sdf(p, sphere1_pos, 0.5, MAT_RED_SPHERE);

    let sphere2_pos = vec3<f32>(
        cos(time * 0.5) * 1.5,
        sin(time * 0.7) * 0.8,
        2.0 + sin(time) * 0.5
    );
    let sphere2 = sphere_sdf(p, sphere2_pos, 0.7, MAT_BLUE_SPHERE);

    let blended_spheres = smin(sphere1, sphere2, 2.8);

    let box = box_sdf(p, vec3<f32>(3.2, 0.0, push_constants.box_z_position), vec3<f32>(1.0), MAT_GREEN_BOX);

    let ground = plane_sdf(p, vec3<f32>(0.0, 1.0, 0.0), 1.5, MAT_GROUND);

    let mirror_sphere = sphere_sdf(p, vec3<f32>(-2.0, 0.0, 3.0), 1.2, MAT_MIRROR_SPHERE);

    var result = blended_spheres;
    if (box.dist < result.dist) {
        result = box;
    }
    if (ground.dist < result.dist) {
        result = ground;
    }
    if (mirror_sphere.dist < result.dist) {
        result = mirror_sphere;
    }

    return result;
}

// Calculate surface normal by sampling the distance field in six directions
fn get_normal(p: vec3<f32>, is_reflection: bool) -> vec3<f32> {
    // Use a larger epsilon for reflections to improve performance
    let epsilon = select(0.001, 0.005, is_reflection);
    let e = vec2<f32>(epsilon, 0.0);

    return normalize(vec3<f32>(
        map_scene(p + e.xyy, is_reflection).dist - map_scene(p - e.xyy, is_reflection).dist,
        map_scene(p + e.yxy, is_reflection).dist - map_scene(p - e.yxy, is_reflection).dist,
        map_scene(p + e.yyx, is_reflection).dist - map_scene(p - e.yyx, is_reflection).dist
    ));
}

// Computes soft shadows by marching from hit point toward light
// k controls shadow softness
fn soft_shadow(ro: vec3<f32>, rd: vec3<f32>, mint: f32, maxt: f32, k: f32, is_reflection: bool) -> f32 {
    var res = 1.0;
    var t = mint;

    // Reduce shadow quality for reflections
    let max_steps = select(32, 8, is_reflection);

    for(var i: i32 = 0; i < max_steps && t < maxt; i++) {
        let h = map_scene(ro + rd * t, is_reflection).dist;
        if(h < 0.001) {
            return 0.0;  // Fully shadowed
        }
        // Higher values of h/t create softer shadows
        res = min(res, k * h / t);
        // Take larger steps for reflections
        t += select(h, h * 2.0, is_reflection);
    }

    return res;
}

// Core raymarching function - returns hit information
struct RayHit {
    hit: bool,
    position: vec3<f32>,
    normal: vec3<f32>,
    material_id: i32,
    distance: f32,
};

fn raymarch_hit(ray_origin: vec3<f32>, ray_direction: vec3<f32>, is_reflection: bool) -> RayHit {
    var t: f32 = 0.0;
    let max_steps = select(512, 64, is_reflection);
    // Use a larger hit distance for reflections (less precision but faster)
    let hit_dist = select(0.01, 0.05, is_reflection);
    const MAX_DIST: f32 = 100.0;

    for(var i: i32 = 0; i < max_steps; i++) {
        let p = ray_origin + t * ray_direction;
        let scene_info = map_scene(p, is_reflection);
        let d = scene_info.dist;

        if(d < hit_dist) {
            let normal = get_normal(p, is_reflection);
            return RayHit(
                true,                 // hit
                p,                    // position
                normal,               // normal
                scene_info.material_id, // material_id
                t                     // distance
            );
        }

        if(t > MAX_DIST) {
            break;
        }

        // Ray marching step - advance by distance to nearest surface
        // Take larger steps for reflections
        t += select(d, d * 1.5, is_reflection);
    }

    // No hit found
    return RayHit(
        false,              // hit
        vec3<f32>(0.0),     // position
        vec3<f32>(0.0),     // normal
        -1,                 // material_id
        MAX_DIST            // distance
    );
}

fn calculate_lighting(position: vec3<f32>, normal: vec3<f32>, material: Material, is_reflection: bool) -> vec3<f32> {
    const AMBIENT: f32 = 0.1;

    // Light properties
    let light_pos = vec3<f32>(2.0, -4.0, -3.0);
    let light_dir = normalize(light_pos - position);
    let light_dist = length(light_pos - position);

    // Diffuse lighting
    let diff = max(dot(normal, light_dir), 0.0);

    // For reflections, we can use simplified shadows or even skip shadows completely
    let shadow = select(
        soft_shadow(position, light_dir, 0.2, light_dist, 16.0, is_reflection),
        0.6, // Use a constant shadow value for deeper reflections
        is_reflection && material.reflectivity > 0.5
    );

    return material.color * (AMBIENT + diff * shadow);
}

// Main raymarching function with reflection support
fn march_ray(ray_origin: vec3<f32>, ray_direction: vec3<f32>) -> vec3<f32> {
    // Define variables for reflection iterations
    var final_color = vec3<f32>(0.0);
    var ray_contribution = 1.0;
    var current_origin = ray_origin;
    var current_direction = ray_direction;

    // Maximum number of reflection bounces
    const MAX_BOUNCES = 3;

    // Perform iterative raymarching with reflections
    for (var bounce = 0; bounce < MAX_BOUNCES; bounce++) {
        // For primary rays use high quality, for reflections use lower quality
        let is_reflection = bounce > 0;

        // Raymarch the current ray
        let hit = raymarch_hit(current_origin, current_direction, is_reflection);

        if (!hit.hit) {
            // If we hit nothing, add background color contribution and exit
            return final_color; // Background is black in this implementation
        }

        // Get material properties
        let material = get_material(hit.material_id, hit.position);

        // Calculate lighting at the hit point
        let direct_lighting = calculate_lighting(hit.position, hit.normal, material, is_reflection);

        // Add the direct lighting contribution to the final color, accounting for reflectivity
        final_color += ray_contribution * (1.0 - material.reflectivity) * direct_lighting;

        // If material is not reflective or we reached max bounces, exit
        if (material.reflectivity < 0.01 || bounce == MAX_BOUNCES - 1) {
            break;
        }

        // Set up next reflection ray
        current_direction = reflect(current_direction, hit.normal);

        // Move origin slightly away from surface to avoid self-intersection
        // Use a larger offset for reflections to avoid precision issues
        let offset = 0.05;
        current_origin = hit.position + hit.normal * offset;

        // Update ray contribution for the next bounce
        ray_contribution *= material.reflectivity;
    }

    return final_color;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    let aspect_ratio = push_constants.size.x / push_constants.size.y;
    let uv = in.clip_position.xy / push_constants.size;

    let adjusted_uv = vec2<f32>(
        (uv.x - 0.7),
        (uv.y - 0.5) * aspect_ratio
    );

    // Create camera rotation matrices based on yaw and pitch inputs
    let cos_yaw = cos(push_constants.camera_yaw);
    let sin_yaw = sin(push_constants.camera_yaw);
    let cos_pitch = cos(push_constants.camera_pitch);
    let sin_pitch = sin(push_constants.camera_pitch);

    // Rotation around Y axis (left/right)
    let rotation_y = mat3x3<f32>(
        cos_yaw, 0.0, -sin_yaw,
        0.0, 1.0, 0.0,
        sin_yaw, 0.0, cos_yaw
    );

    // Rotation around X axis (up/down)
    let rotation_x = mat3x3<f32>(
        1.0, 0.0, 0.0,
        0.0, cos_pitch, sin_pitch,
        0.0, -sin_pitch, cos_pitch
    );

    let camera_pos = vec3<f32>(0.0, 0.0, -3.0);
    // Apply camera rotations to the ray direction
    let ray_direction = normalize(rotation_y * rotation_x * vec3<f32>(adjusted_uv.x, adjusted_uv.y, 1.0));

    // Perform raymarching with reflection
    let colour = march_ray(camera_pos, ray_direction);

    let tone_mapped = colour / (colour + 1.0);

    return vec4<f32>(tone_mapped, 1.0);
}
