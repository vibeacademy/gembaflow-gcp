# Agile Flow GCP - Manual Acceptance Test Specification

## Overview

This document defines the manual acceptance tests for the Agile Flow GCP application to validate it's fit for release.

## Test Categories

### 1. Application Startup
- **T1.1**: Local development server starts successfully
- **T1.2**: Dependencies are properly installed
- **T1.3**: Environment configuration is loaded correctly

### 2. Health Check Endpoints
- **T2.1**: Basic health check endpoint (`/api/health`) returns 200
- **T2.2**: Database health check endpoint (`/api/health/db`) returns 200
- **T2.3**: Health checks return proper JSON format

### 3. Database Connectivity
- **T3.1**: Database connection is established successfully
- **T3.2**: Database migrations run without errors
- **T3.3**: Basic CRUD operations work (via todo endpoints)

### 4. Authentication System
- **T4.1**: Login page loads correctly
- **T4.2**: Auth middleware functions properly
- **T4.3**: Session management works (if configured)

### 5. Core Todo Functionality
- **T5.1**: Home page loads and displays existing todos
- **T5.2**: New todo creation works via POST /todos
- **T5.3**: Todo list displays properly with HTMX integration
- **T5.4**: Todo operations return appropriate HTML responses

### 6. Static Assets
- **T6.1**: Static files are served correctly
- **T6.2**: CSS styling is applied properly
- **T6.3**: Favicon and other assets load

### 7. Error Handling
- **T7.1**: 404 pages return appropriate responses
- **T7.2**: Application handles missing environment variables gracefully
- **T7.3**: Database connection failures are handled properly

## Test Execution Requirements

- Tests run against local development environment
- Database should be available (Neon dev branch or local)
- All environment variables properly configured
- Server runs on port 8080

## Pass Criteria

- All endpoints return expected HTTP status codes
- No critical errors in server logs
- Database operations complete successfully
- Authentication flows work as designed
- Static assets load without errors

## Execution Environment

- Python 3.12+ with uv package manager
- FastAPI application server
- Database: Neon Postgres (or configured alternative)
- Authentication: Firebase (if configured)