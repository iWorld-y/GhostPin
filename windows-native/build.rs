use std::{env, path::PathBuf, process::Command};

fn main() {
    println!("cargo:rerun-if-changed=resources/GhostPin.rc");
    println!("cargo:rerun-if-changed=resources/GhostPin.ico");
    println!("cargo:rerun-if-changed=resources/GhostPin.manifest");

    let out_dir = PathBuf::from(env::var_os("OUT_DIR").expect("OUT_DIR is set by Cargo"));
    let resource = out_dir.join("GhostPinNative.res");
    let status = Command::new("rc.exe")
        .args(["/nologo", "/fo"])
        .arg(&resource)
        .arg("resources/GhostPin.rc")
        .status()
        .expect("rc.exe must be available in the VS Developer environment");
    assert!(status.success(), "rc.exe failed with status {status}");

    println!(
        "cargo:rustc-link-arg-bin=ghostpin-native={}",
        resource.display()
    );
}
