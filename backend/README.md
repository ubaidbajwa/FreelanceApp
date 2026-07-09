# FreelanceApp — Backend

Production-grade freelance marketplace backend built with **ASP.NET Core 8**.

## 🚀 Features Implemented

### Authentication System
- JWT-based authentication with Redis refresh tokens
- Email verification with OTP (CSPRNG-based)
- Password reset with **Token Versioning** for multi-device session revocation
- Rate limiting, email enumeration protection
- Custom JWT validation middleware

### KYC Verification (AI-Powered)
- CNIC/Passport document upload (Cloudinary)
- OCR using **Google Cloud Vision API**
- Face matching using **AWS Rekognition** (70% threshold)
- Automatic verification flow

## 🏗️ Architecture

Clean Architecture with 4 layers:
- **Domain** — Entities, enums (no dependencies)
- **Application** — Business logic, interfaces, DTOs
- **Infrastructure** — EF Core, external services
- **API** — Controllers, middleware

## 🛠️ Tech Stack

- ASP.NET Core 8
- EF Core 8 + PostgreSQL (Neon)
- Redis (Upstash) for sessions
- JWT + BCrypt
- Cloudinary, Google Cloud Vision, AWS Rekognition
- MailKit (email)

## 📋 Status

🚧 **Under active development**

✅ Authentication system  
✅ KYC verification  
⏳ Job posting & bidding  
⏳ Payment & escrow  
⏳ Real-time chat  

## 🔒 Security Patterns

- Defense in depth (multi-layer security)
- Idempotent operations
- Silent failure for enumeration protection
- Token versioning for instant session revocation
- BCrypt password hashing
- HTTPS only

---

**Author:** Ubaid Bajwa  
**Status:** Learning project — actively developed
