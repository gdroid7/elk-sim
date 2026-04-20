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
		LogCount:   6,
		StartTime:  startTime,
	})

	runScenario(log, *compressTime)
}

func runScenario(log *logger.Logger, compress bool) {
	sleep := func() {
		if !compress {
			time.Sleep(1000 * time.Millisecond)
		}
	}

	// Legitimate user - successful login
	log.Info("Login successful",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-2301",
		"ip_address", "192.168.1.45",
	)
	sleep()

	// Attacker - brute force on USR-1042
	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-1042",
		"ip_address", "203.0.113.87",
		"attempt_count", 1,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-1042",
		"ip_address", "203.0.113.87",
		"attempt_count", 2,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	// Legitimate user - successful login
	log.Info("Login successful",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-5678",
		"ip_address", "10.0.2.112",
	)
	sleep()

	// Attacker continues
	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-1042",
		"ip_address", "203.0.113.87",
		"attempt_count", 3,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-1042",
		"ip_address", "203.0.113.87",
		"attempt_count", 4,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	// Different attacker on different user
	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-8901",
		"ip_address", "198.51.100.42",
		"attempt_count", 1,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	// First attacker final attempt
	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-1042",
		"ip_address", "203.0.113.87",
		"attempt_count", 5,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Error("Account locked",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-1042",
		"ip_address", "203.0.113.87",
		"attempt_count", 5,
		"error_code", "ACCOUNT_LOCKED",
	)
	sleep()

	// Second attacker continues
	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-8901",
		"ip_address", "198.51.100.42",
		"attempt_count", 2,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-8901",
		"ip_address", "198.51.100.42",
		"attempt_count", 3,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	// Legitimate user - typo then success
	log.Warn("Login failed",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-3456",
		"ip_address", "172.16.0.88",
		"attempt_count", 1,
		"error_code", "INVALID_PASSWORD",
	)
	sleep()

	log.Info("Login successful",
		"scenario", "auth-brute-force",
		"service", "auth-service",
		"user_id", "USR-3456",
		"ip_address", "172.16.0.88",
	)
}
