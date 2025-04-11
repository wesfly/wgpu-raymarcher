#[repr(C)]
#[derive(Copy, Clone, Debug, bytemuck::Pod, bytemuck::Zeroable)]
pub struct Vertex {
    position: [f32; 2],
}

pub const VERTICES: &[Vertex] = &[
    Vertex {
        position: [-2.0, 2.0],
    },
    Vertex {
        position: [-2.0, -2.0],
    },
    Vertex {
        position: [2.0, -2.0],
    },
    Vertex {
        position: [2.0, 2.0],
    },
];

pub const INDICES: &[u8] = &[0, 1, 2, 0, 2, 3];
