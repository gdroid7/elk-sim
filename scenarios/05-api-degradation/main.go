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
		LogCount:   10,
		StartTime:  startTime,
	})

	runScenario(log, *compressTime)
}

func runScenario(log *logger.Logger, compress bool) {
	sleep := func() {
		if !compress {
			time.Sleep(900 * time.Millisecond)
		}
	}

	log.Info("API request",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/products",
		"status_code", 200,
		"latency_ms", 45,
	)
	sleep()

	log.Info("API request",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/products",
		"status_code", 200,
		"latency_ms", 52,
	)
	sleep()

	log.Warn("High latency",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/products",
		"status_code", 200,
		"latency_ms", 420,
		"error_code", "HIGH_LATENCY",
	)
	sleep()

	log.Warn("High latency",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/orders",
		"status_code", 200,
		"latency_ms", 680,
		"error_code", "HIGH_LATENCY",
	)
	sleep()

	log.Warn("High latency",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/products",
		"status_code", 200,
		"latency_ms", 950,
		"error_code", "HIGH_LATENCY",
	)
	sleep()

	log.Error("Upstream timeout",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/products",
		"status_code", 504,
		"latency_ms", 3000,
		"error_code", "UPSTREAM_TIMEOUT",
	)
	sleep()

	log.Error("Upstream timeout",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/orders",
		"status_code", 504,
		"latency_ms", 3000,
		"error_code", "UPSTREAM_TIMEOUT",
	)
	sleep()

	log.Error("Service unavailable",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/products",
		"status_code", 503,
		"latency_ms", 5000,
		"error_code", "SERVICE_UNAVAILABLE",
	)
	sleep()

	log.Error("Service unavailable",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/orders",
		"status_code", 503,
		"latency_ms", 5000,
		"error_code", "SERVICE_UNAVAILABLE",
	)
	sleep()

	log.Error("Circuit breaker open",
		"scenario", "api-degradation",
		"endpoint", "/api/v1/*",
		"status_code", 503,
		"latency_ms", 0,
		"error_code", "CIRCUIT_BREAKER_OPEN",
	)
}
