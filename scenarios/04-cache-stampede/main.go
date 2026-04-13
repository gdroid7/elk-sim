package main

import (
	"flag"
	"time"

	"github.com/statucred/go-simulator/internal/logger"
)

func main() {
	tz := flag.String("tz", "Asia/Kolkata", "timezone")
	compressTime := flag.Bool("compress-time", false, "compress timestamps")
	timeWindow := flag.Duration("time-window", 10*time.Minute, "simulated window")
	logFile := flag.String("log-file", "", "log file path (optional)")
	flag.Parse()

	loc, err := time.LoadLocation(*tz)
	if err != nil {
		loc = time.UTC
	}
	startTime := time.Now().In(loc)
	if *compressTime {
		startTime = startTime.Add(-*timeWindow)
	}
	log := logger.New(logger.Config{
		FilePath:   *logFile,
		TZ:         loc,
		Compress:   *compressTime,
		TimeWindow: *timeWindow,
		LogCount:   12,
		StartTime:  startTime,
	})

	runScenario(log, *compressTime)
}

func runScenario(log *logger.Logger, compress bool) {
	sleep := func() {
		if !compress {
			time.Sleep(500 * time.Millisecond)
		}
	}

	log.Info("Cache hit",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", true,
		"latency_ms", 2,
	)
	sleep()

	log.Info("Cache hit",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", true,
		"latency_ms", 3,
	)
	sleep()

	log.Warn("Cache miss",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 1,
		"latency_ms", 45,
	)
	sleep()

	log.Warn("Cache miss",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 1,
		"latency_ms", 48,
	)
	sleep()

	log.Warn("Cache miss",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 1,
		"latency_ms", 52,
	)
	sleep()

	log.Error("DB overload — stampede detected",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 47,
		"latency_ms", 380,
	)
	sleep()

	log.Error("DB overload — stampede detected",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 93,
		"latency_ms", 720,
	)
	sleep()

	log.Error("DB overload — stampede detected",
		"scenario", "cache-stampede",
		"cache_key", "user:session:store",
		"hit", false,
		"db_calls", 61,
		"latency_ms", 640,
	)
	sleep()

	log.Error("DB overload — stampede detected",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 128,
		"latency_ms", 1100,
	)
	sleep()

	log.Error("DB connection timeout",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 200,
		"latency_ms", 5000,
	)
	sleep()

	log.Error("DB connection timeout",
		"scenario", "cache-stampede",
		"cache_key", "user:session:store",
		"hit", false,
		"db_calls", 174,
		"latency_ms", 5000,
	)
	sleep()

	log.Error("Cache layer unavailable",
		"scenario", "cache-stampede",
		"cache_key", "product:catalog:v3",
		"hit", false,
		"db_calls", 0,
		"latency_ms", 5000,
	)
}
