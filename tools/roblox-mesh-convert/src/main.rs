use std::{env, fs, io::Write, path::{Path, PathBuf}};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: roblox-mesh-convert <input-dir> <output-dir>");
        std::process::exit(2);
    }
    let input = PathBuf::from(&args[1]);
    let output = PathBuf::from(&args[2]);
    fs::create_dir_all(&output)?;

    let mut ok = 0usize;
    let mut failed = 0usize;
    for entry in fs::read_dir(&input)? {
        let entry = entry?;
        let path = entry.path();
        if path.extension().and_then(|s| s.to_str()) != Some("mesh") { continue; }
        match convert_one(&path, &output) {
            Ok(()) => { ok += 1; println!("OBJ_OK {}", path.display()); }
            Err(err) => { failed += 1; eprintln!("OBJ_FAIL {}: {}", path.display(), err); }
        }
    }
    println!("OBJ_DONE ok={} failed={}", ok, failed);
    if ok == 0 { return Err("no meshes converted".into()); }
    Ok(())
}

fn convert_one(path: &Path, output: &Path) -> Result<(), Box<dyn std::error::Error>> {
    let bytes = fs::read(path)?;
    let mesh = rbx_mesh::parse(&bytes)?;
    let faces = mesh.lod0();
    let stem = path.file_stem().and_then(|s| s.to_str()).ok_or("bad filename")?;
    let out_path = output.join(format!("{}.obj", stem));
    let mut out = fs::BufWriter::new(fs::File::create(out_path)?);

    writeln!(out, "# Roblox FileMesh {}", mesh.version)?;
    writeln!(out, "# vertices {} faces {} lods {}", mesh.vertices.len(), faces.len(), mesh.lod_count())?;
    for v in &mesh.vertices {
        writeln!(out, "v {:.9} {:.9} {:.9}", v.position[0], v.position[1], v.position[2])?;
    }
    for v in &mesh.vertices {
        writeln!(out, "vt {:.9} {:.9}", v.uv[0], 1.0 - v.uv[1])?;
    }
    for v in &mesh.vertices {
        writeln!(out, "vn {:.9} {:.9} {:.9}", v.normal[0], v.normal[1], v.normal[2])?;
    }
    for f in faces {
        let a = f[0] + 1;
        let b = f[1] + 1;
        let c = f[2] + 1;
        writeln!(out, "f {0}/{0}/{0} {1}/{1}/{1} {2}/{2}/{2}", a, b, c)?;
    }
    Ok(())
}
