package main

import (
	"bufio"
	"context"
	"embed"
	"encoding/json"
	"fmt"
	"io"
	"io/fs"
	"log"
	"net/http"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
	"time"

	"github.com/statucred/go-simulator/internal/scenarios"
)

//go:embed web
var webFS embed.FS

func main() {
	if err := os.MkdirAll("logs", 0755); err != nil {
		log.Fatalf("mkdir logs: %v", err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("GET /", indexHandler)
	mux.HandleFunc("GET /api/scenarios", scenariosHandler)
	mux.HandleFunc("GET /api/run/{id}", runHandler)
	mux.HandleFunc("GET /api/status", statusHandler)

	addr := ":8080"
	log.Printf("Listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

func indexHandler(w http.ResponseWriter, r *http.Request) {
	sub, err := fs.Sub(webFS, "web")
	if err != nil {
		http.Error(w, "web not found", 500)
		return
	}
	http.FileServer(http.FS(sub)).ServeHTTP(w, r)
}

func scenariosHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(scenarios.All())
}

func runHandler(w http.ResponseWriter, r *http.Request) {
	id := r.PathValue("id")
	if !isValidScenarioID(id) {
		http.Error(w, "invalid scenario id", 400)
		return
	}
	meta, ok := scenarios.Get(id)
	if !ok {
		http.Error(w, "scenario not found", 404)
		return
	}

	compress := r.URL.Query().Get("compress") != "false"
	tz := r.URL.Query().Get("tz")
	if tz == "" {
		tz = "Asia/Kolkata"
	}

	logFile := filepath.Join("logs", "sim-"+id+".log")
	args := []string{"--tz=" + tz, "--log-file=" + logFile}
	if compress {
		args = append(args, "--compress-time")
	}

	ctx, cancel := context.WithTimeout(r.Context(), 2*time.Minute)
	defer cancel()

	binPath := meta.BinPath

	// If the path is a directory, run the scenario source via `go run`.
	// Otherwise, execute the binary directly (fallback for pre-built binaries).
	info, err := os.Stat(binPath)
	var cmd *exec.Cmd
	if err == nil && info.IsDir() {
		cmd = exec.CommandContext(ctx, "go", append([]string{"run", "./" + binPath}, args...)...)
	} else {
		cmd = exec.CommandContext(ctx, binPath, args...)
	}

	pr, pw := io.Pipe()
	defer pr.Close()
	cmd.Stdout = pw
	cmd.Stderr = pw

	w.Header().Set("Content-Type", "text/event-stream")
	w.Header().Set("Cache-Control", "no-cache")
	w.Header().Set("Connection", "keep-alive")
	w.Header().Set("Access-Control-Allow-Origin", "*")

	flusher, ok := w.(http.Flusher)
	if !ok {
		http.Error(w, "streaming not supported", 500)
		return
	}

	if err := cmd.Start(); err != nil {
		pw.CloseWithError(err)
		fmt.Fprintf(w, "data: {\"error\":%q}\n\n", err.Error())
		flusher.Flush()
		return
	}

	go func() {
		if err := cmd.Wait(); err != nil {
			pw.CloseWithError(err)
		} else {
			pw.Close()
		}
	}()

	scanner := bufio.NewScanner(pr)
	for scanner.Scan() {
		select {
		case <-ctx.Done():
			return
		default:
		}
		line := scanner.Text()
		if strings.TrimSpace(line) == "" {
			continue
		}
		fmt.Fprintf(w, "data: %s\n\n", line)
		flusher.Flush()
	}

	if err := scanner.Err(); err != nil {
		log.Printf("scenario %s error: %v", id, err)
		fmt.Fprintf(w, "data: {\"error\":%q}\n\n", err.Error())
		flusher.Flush()
		return
	}

	fmt.Fprintf(w, "data: [DONE]\n\n")
	flusher.Flush()
}

func statusHandler(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(map[string]string{"status": "ok", "elk": "up"})
}

func isValidScenarioID(id string) bool {
	for _, c := range id {
		if !((c >= 'a' && c <= 'z') || (c >= '0' && c <= '9') || c == '-') {
			return false
		}
	}
	return len(id) > 0 && len(id) <= 64
}
