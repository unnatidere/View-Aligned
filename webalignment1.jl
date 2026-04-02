using HTTP
using Sockets
using Dates

# --- 1. CONFIGURATION ---
# Ensure these paths exist on your system
BASE_DIR   = "/mnt/d/Unnati/Msc_II/SN/miniproj/alignment_app"
UPLOAD_DIR = joinpath(BASE_DIR, "uploads")
OUT_DIR    = joinpath(BASE_DIR, "output")

mkpath(UPLOAD_DIR)
mkpath(OUT_DIR)

# --- 2. BIOINFORMATICS PIPELINE ---
function run_pipeline(ref_path, reads_path, output_prefix)
    bam_out = output_prefix * ".sorted.bam"
    stats_out = output_prefix * ".stats.txt"
    
    try
        # Step A: Indexing reference
        if !isfile(ref_path * ".bwt")
            @info "Indexing reference..."
            run(`bwa index "$ref_path"`)
        end
        if !isfile(ref_path * ".fai")
            run(`samtools faidx "$ref_path"`)
        end

        # Step B: Align & Sort
        @info "Running Alignment..."
        pipeline_cmd = pipeline(
            `bwa mem -t 4 "$ref_path" "$reads_path"`,
            `samtools view -Sb -`,
            `samtools sort -o "$bam_out"`
        )
        run(pipeline_cmd)

        # Step C: Index the BAM
        run(`samtools index "$bam_out"`)

        # Step D: Generate Statistics
        @info "Generating Mapping Stats..."
        stats_data = read(`samtools flagstat "$bam_out"`, String)
        write(stats_out, stats_data)
        
        return bam_out, stats_data
    catch e
        @error "Pipeline Error" exception=e
        return nothing, nothing
    end
end

# Helper to get the first sequence name from FASTA
function get_fasta_locus(ref_path)
    for line in eachline(ref_path)
        if startswith(line, ">")
            return split(replace(line, ">" => ""))[1]
        end
    end
    return "all"
end

# --- 3. VIEWER HTML (Results Page) ---
function viewer_html(bam_filename, ref_filename, locus_name, stats_text)
    formatted_stats = replace(stats_text, "\n" => "<br>")

    return """
    <html>
    <head>
        <title>VIEW ALIGNED</title>
        <script src="https://cdn.jsdelivr.net/npm/igv@2.15.5/dist/igv.min.js"></script>
        <style>
            body { font-family: 'Segoe UI', sans-serif; padding: 30px; background-color: #f4f7f6; color: #333; }
            .container { max-width: 1100px; margin: auto; background: white; padding: 25px; border-radius: 12px; box-shadow: 0 4px 15px rgba(0,0,0,0.05); }
            .header-info { display: flex; justify-content: space-between; align-items: center; border-bottom: 2px solid #eee; padding-bottom: 15px; margin-bottom: 20px; }
            .stats-box { background: #f8f9fa; padding: 20px; border-left: 5px solid #28a745; font-family: 'Courier New', monospace; font-size: 0.85em; margin-bottom: 25px; overflow-x: auto; }
            h2 { margin: 0; color: #2c3e50; }
            #igv-div { border: 1px solid #ddd; border-radius: 8px; background: white; }
        </style>
    </head>
    <body>
        <div class="container">
            <div class="header-info">
                <h2> Alignment Analysis</h2>
                <div style="text-align: right; font-size: 0.9em; color: #666;">
                    <strong>Ref:</strong> $ref_filename <br>
                    <strong>Locus:</strong> $locus_name
                </div>
            </div>

            <div class="stats-box">
                <strong> Mapping Quality Report (samtools flagstat):</strong><br><br>
                $formatted_stats
            </div>

            <div id="igv-div"></div>
        </div>

        <script type="text/javascript">
            var igvDiv = document.getElementById("igv-div");
            var options = {
                reference: {
                    id: "$locus_name",
                    fastaURL: "/download_ref/$ref_filename",
                    indexURL: "/download_ref/$ref_filename.fai"
                },
                locus: "$locus_name",
                tracks: [
                    {
                        name: "Aligned Reads",
                        url: "/download/$bam_filename",
                        indexURL: "/download/$bam_filename.bai",
                        format: "bam",
                        type: "alignment",
                        displayMode: "EXPANDED",
                        height: 400
                    }
                ]
            };
            igv.createBrowser(igvDiv, options);
        </script>
    </body>
    </html>
    """
end

# --- 4. SERVER LOGIC ---
@info "Server starting at http://localhost:8001"
HTTP.serve("0.0.0.0", 8001) do req::HTTP.Request

    # File Download Routes
    if startswith(req.target, "/download/")
        fname = replace(req.target, "/download/" => "")
        fpath = joinpath(OUT_DIR, fname)
        isfile(fpath) && return HTTP.Response(200, ["Access-Control-Allow-Origin" => "*"], read(fpath))
    end

    if startswith(req.target, "/download_ref/")
        fname = replace(req.target, "/download_ref/" => "")
        fpath = joinpath(UPLOAD_DIR, fname)
        isfile(fpath) && return HTTP.Response(200, ["Access-Control-Allow-Origin" => "*"], read(fpath))
    end

    # GET: Form Page (Centered UI)
    if req.method == "GET" && req.target == "/"
        return HTTP.Response(200, ["Content-Type" => "text/html"], 
            """
            <html>
            <head>
                <title>VI</title>
                <style>
                    body { font-family: 'Segoe UI', sans-serif; background: #e9ecef; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; }
                    .card { background: white; padding: 40px; border-radius: 15px; box-shadow: 0 10px 25px rgba(0,0,0,0.1); width: 400px; text-align: center; }
                    h2 { color: #333; margin-bottom: 10px; }
                    p { color: #777; margin-bottom: 30px; font-size: 0.9em; }
                    .group { text-align: left; margin-bottom: 20px; }
                    label { display: block; margin-bottom: 8px; font-weight: 600; color: #495057; }
                    input[type='file'] { width: 100%; padding: 10px; border: 1px solid #ced4da; border-radius: 5px; box-sizing: border-box; }
                    input[type='submit'] { background: #007bff; color: white; border: none; padding: 14px; width: 100%; border-radius: 5px; font-size: 16px; font-weight: bold; cursor: pointer; transition: 0.3s; }
                    input[type='submit']:hover { background: #0056b3; }
                </style>
            </head>
            <body>
                <div class='card'>
                    <h2>VIEW ALIGNED</h2>
                    <p>A GUI powered integrated tool, that allows both alignment and visualization of your reads.</p>
	            <p>A true mate for Biologists turned Bioinformaticians!<p>
                    <form method='POST' action='/align' enctype='multipart/form-data' onsubmit="this.btn.value='Aligning...'; this.btn.disabled=true;">
                        <div class='group'>
                            <label>Reference FASTA (.fa)</label>
                            <input type='file' name='ref' required>
                        </div>
                        <div class='group'>
                            <label>Read FASTQ (.fastq)</label>
                            <input type='file' name='reads' required>
                        </div>
                        <input type='submit' name='btn' value='Align & View Results'>
                    </form>
                </div>
            </body>
            </html>
            """)
    end

    # POST: Run Pipeline
    if req.method == "POST" && req.target == "/align"
        try
            parts = HTTP.parse_multipart_form(req)
            local ref_path, reads_path, ref_filename
            
            for p in parts
                if p.name == "ref"
                    ref_filename = p.filename
                    ref_path = joinpath(UPLOAD_DIR, p.filename)
                    write(ref_path, p.data)
                elseif p.name == "reads"
                    reads_path = joinpath(UPLOAD_DIR, p.filename)
                    write(reads_path, p.data)
                end
            end

            locus_name = get_fasta_locus(ref_path)
            timestamp = Dates.format(now(), "HHmmss")
            bam_name = "result_$timestamp.sorted.bam"
            out_prefix = joinpath(OUT_DIR, "result_$timestamp")
            
            bam_path, stats_data = run_pipeline(ref_path, reads_path, out_prefix)

            if bam_path !== nothing
                return HTTP.Response(200, ["Content-Type" => "text/html"], 
                    viewer_html(bam_name, ref_filename, locus_name, stats_data))
            end
        catch e
            return HTTP.Response(500, "Server Error: $e")
        end
    end

    return HTTP.Response(404, "Not Found")
end