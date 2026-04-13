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

	log.Info("Query executed",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 12,
	)
	sleep()

	log.Info("Query executed",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 18,
	)
	sleep()

	log.Warn("Slow query detected",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 210,
		"error_code", "SLOW_QUERY",
	)
	sleep()

	log.Warn("Slow query detected",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 340,
		"error_code", "SLOW_QUERY",
	)
	sleep()

	log.Warn("Slow query detected",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "products",
		"duration_ms", 289,
		"error_code", "SLOW_QUERY",
	)
	sleep()

	log.Error("Query SLA breach",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 520,
		"error_code", "SLA_BREACH",
	)
	sleep()

	log.Error("Query SLA breach",
		"scenario", "db-slow-query",
		"query_type", "UPDATE",
		"table", "inventory",
		"duration_ms", 610,
		"error_code", "SLA_BREACH",
	)
	sleep()

	log.Error("Query SLA breach",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 980,
		"error_code", "SLA_BREACH",
	)
	sleep()

	log.Error("Query timeout",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 5000,
		"error_code", "QUERY_TIMEOUT",
	)
	sleep()

	log.Error("DB connection pool exhausted",
		"scenario", "db-slow-query",
		"query_type", "SELECT",
		"table", "orders",
		"duration_ms", 5000,
		"error_code", "POOL_EXHAUSTED",
	)
}
