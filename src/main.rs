// real magic happens in lib.rs and shader.wgsl

use wgpu_raymarching::run;

fn main() {
    pollster::block_on(run());
}
