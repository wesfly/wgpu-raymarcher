// real magic happens in lib.rs and shader.wgsl

use pollster::block_on;
use wgpu_raymarching::run;

fn main() {
    block_on(run());
}
