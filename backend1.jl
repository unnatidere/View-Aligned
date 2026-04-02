#!/usr/bin/env julia

using Dates

# -------------------------------
# 0️⃣ Helper: Convert Windows path to WSL path
# -------------------------------
function win_to_wsl(winpath::String)
    # Example: D:\Unnati\file -> /mnt/d/Unnati/file
    m = match(r"^([A-Za-z]):\\(.*)", winpath)
    if m === nothing
        error("Invalid Windows path: $winpath")
    end
    drive, rest = m.captures
    wslpath = "/mnt/$(lowercase(drive))/" * replace(rest, "\\" => "/")
    return wslpath
end

# -------------------------------
# 1️⃣ Define input files (Windows paths)
# -------------------------------
win_ref = raw"D:\Unnati\Msc II\SN\miniproj\alignment_app\uploads\genome1.fa"
win_reads = raw"D:\Unnati\Msc II\SN\miniproj\alignment_app\uploads\reads1.fastq"

ref = win_to_wsl(win_ref)
reads = win_to_wsl(win_reads)

# Output SAM file with timestamp
timestamp = Dates.format(now(), "yyyy-mm-ddTHH:MM:SS")
sam = "/mnt/d/Unnati/Msc II/SN/miniproj/alignment_app/aln_$timestamp.sam"

println("Reference genome: $ref")
println("Reads file: $reads")
println("Output SAM: $sam")

# -------------------------------
# 2️⃣ Check files exist
# -------------------------------
if !isfile(ref)
    error("❌ Reference genome not found at $ref")
end
if !isfile(reads)
    error("❌ Reads file not found at $reads")
end

# -------------------------------
# 3️⃣ Check if BWA is installed
# -------------------------------
function bwa_exists()
    try
        return success(`which bwa`)
    catch
        return false
    end
end

if !bwa_exists()
    error("""
❌ BWA is not installed or not in PATH.

Install using:
▶ Linux/WSL: sudo apt install bwa
▶ Conda: conda install -c bioconda bwa
▶ Mac: brew install bwa
▶ Windows: download bwa.exe and add to PATH
""")
end
println("✅ BWA found")

# -------------------------------
# 4️⃣ Create BWA index if missing
# -------------------------------
index_files = [
    ref * ".amb",
    ref * ".ann",
    ref * ".bwt",
    ref * ".pac",
    ref * ".sa"
]

if !all(isfile, index_files)
    println("🔧 Creating BWA index...")
    run(`bwa index $ref`)
else
    println("✅ BWA index already exists")
end

# -------------------------------
# 5️⃣ Run BWA MEM safely
# -------------------------------
try
    println("Running BWA MEM...")

    # Redirect stdout to SAM file
    open(sam, "w") do sam_io
        run(pipeline(`bwa mem $ref $reads`, sam_io))
    end

    println("✅ Alignment complete. SAM file created at $sam")
catch e
    println("❌ Error running BWA: $e")
end

# -------------------------------
# 6️⃣ Optional: Launch IGV (Web version)
# -------------------------------
println("You can now open IGV and load the reference and SAM file for visualization.")
println("Example: https://igv.org/app/")
