package main

import (
	"crypto/tls"
	"crypto/x509"
	"encoding/json"
	"fmt"
	"io/ioutil"
	"log"
	"net/http"
	"strings"
	"time"
)

type ImageReview struct {
	ApiVersion string `json:"apiVersion"`
	Kind       string `json:"kind"`
	Spec       struct {
		Containers []struct {
			Image string `json:"image"`
		} `json:"containers"`
	} `json:"spec"`
	Status struct {
		Allowed bool   `json:"allowed"`
		Reason  string `json:"reason,omitempty"`
	} `json:"status"`
}

func validate(w http.ResponseWriter, r *http.Request) {
	log.Printf("Received image policy webhook request from %s", r.RemoteAddr)

	var review ImageReview
	if err := json.NewDecoder(r.Body).Decode(&review); err != nil {
		log.Printf("Error decoding request: %v", err)
		http.Error(w, "Invalid request", http.StatusBadRequest)
		return
	}

	// Blacklist of vulnerable images
	blacklistedImages := []string{
		"nginx:1.19",
		"nginx:1.18",
		"ubuntu:18.04",
	}

	review.Status.Allowed = true

	for _, container := range review.Spec.Containers {
		log.Printf("Checking image: %s", container.Image)

		for _, blacklisted := range blacklistedImages {
			if strings.Contains(container.Image, blacklisted) {
				review.Status.Allowed = false
				review.Status.Reason = fmt.Sprintf("SECURITY: Image %s is forbidden (contains known vulnerabilities). Use a more recent version.", container.Image)
				log.Printf("BLOCKED: %s", container.Image)
				break
			}
		}

		if !review.Status.Allowed {
			break
		}
	}

	if review.Status.Allowed {
		log.Printf("ALLOWED: All images passed security check")
	}

	w.Header().Set("Content-Type", "application/json")
	if err := json.NewEncoder(w).Encode(review); err != nil {
		log.Printf("Error encoding response: %v", err)
	}
}

func health(w http.ResponseWriter, r *http.Request) {
	w.WriteHeader(http.StatusOK)
	w.Write([]byte("OK"))
}

func setupTLS() (*tls.Config, error) {
	// Load server certificate and key
	cert, err := tls.LoadX509KeyPair("/etc/webhook-certs/tls.crt", "/etc/webhook-certs/tls.key")
	if err != nil {
		return nil, fmt.Errorf("failed to load TLS certificates: %v", err)
	}

	// Load CA certificate for client verification (if needed)
	caCertPEM, err := ioutil.ReadFile("/etc/webhook-ca/ca.crt")
	if err != nil {
		log.Printf("Warning: Could not load CA certificate: %v", err)
		// Continue without CA verification
		return &tls.Config{
			Certificates: []tls.Certificate{cert},
			ServerName:   "image-policy-webhook.kube-system.svc",
		}, nil
	}

	caCertPool := x509.NewCertPool()
	if !caCertPool.AppendCertsFromPEM(caCertPEM) {
		log.Printf("Warning: Failed to parse CA certificate")
	}

	tlsConfig := &tls.Config{
		Certificates: []tls.Certificate{cert},
		ServerName:   "image-policy-webhook.kube-system.svc",
		RootCAs:      caCertPool,
		ClientCAs:    caCertPool,
		// ClientAuth can be set to RequireAndVerifyClientCert for mutual TLS
		ClientAuth: tls.NoClientCert,
	}

	return tlsConfig, nil
}

func validateCertificates() {
	// Check certificate expiration
	cert, err := tls.LoadX509KeyPair("/etc/webhook-certs/tls.crt", "/etc/webhook-certs/tls.key")
	if err != nil {
		log.Fatalf("Failed to load certificates for validation: %v", err)
	}

	if len(cert.Certificate) > 0 {
		x509Cert, err := x509.ParseCertificate(cert.Certificate[0])
		if err != nil {
			log.Printf("Warning: Failed to parse certificate: %v", err)
			return
		}

		now := time.Now()
		if now.After(x509Cert.NotAfter) {
			log.Fatalf("Server certificate has expired: %v", x509Cert.NotAfter)
		}

		if now.Before(x509Cert.NotBefore) {
			log.Fatalf("Server certificate is not yet valid: %v", x509Cert.NotBefore)
		}

		// Warn if certificate expires soon (within 7 days)
		if now.Add(7 * 24 * time.Hour).After(x509Cert.NotAfter) {
			log.Printf("WARNING: Server certificate will expire soon: %v", x509Cert.NotAfter)
		}

		log.Printf("Server certificate is valid until: %v", x509Cert.NotAfter)
		log.Printf("Certificate subject: %s", x509Cert.Subject)
		log.Printf("Certificate DNS names: %v", x509Cert.DNSNames)
	}
}

func main() {
	log.Println("Starting Image Policy Webhook server...")

	// Validate certificates on startup
	validateCertificates()

	http.HandleFunc("/scan", validate)
	http.HandleFunc("/health", health)

	// Setup TLS configuration
	tlsConfig, err := setupTLS()
	if err != nil {
		log.Fatalf("Failed to setup TLS: %v", err)
	}

	server := &http.Server{
		Addr:      ":8080",
		TLSConfig: tlsConfig,
		// Add timeouts for security
		ReadTimeout:  30 * time.Second,
		WriteTimeout: 30 * time.Second,
		IdleTimeout:  120 * time.Second,
	}

	log.Println("Image Policy Webhook server starting on :8080")
	log.Println("TLS configuration loaded successfully")
	log.Fatal(server.ListenAndServeTLS("", ""))
}