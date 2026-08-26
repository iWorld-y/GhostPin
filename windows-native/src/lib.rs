#![deny(unsafe_op_in_unsafe_fn)]
#![deny(clippy::undocumented_unsafe_blocks)]

pub mod codec;
pub mod core;
pub mod diagnostics;
pub mod lifecycle;
pub mod platform;
pub mod render;
pub mod settings;
pub mod storage;
pub mod watcher;
