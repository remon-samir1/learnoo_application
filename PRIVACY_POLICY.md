# Privacy Policy for [App Name]

**Last Updated:** May 1, 2026

## 1. Introduction

[App Name] ("we," "our," or "us") is committed to protecting your privacy. This Privacy Policy explains how we collect, use, store, and protect your personal information when you use our e-learning mobile application.

By using [App Name], you agree to the collection and use of information in accordance with this policy.

## 2. Information We Collect

### 2.1 Personal Information You Provide
- **Account Information**: First name, last name, email address, phone number, and password when you register
- **Academic Information**: University, faculty, and educational center affiliations
- **Profile Photos**: Images you upload for your profile (optional)

### 2.2 Device Information
- **Device Name**: Brand and model (e.g., "Samsung Galaxy S23") collected during login/registration for security purposes
- **Device Type**: Operating system version (Android/iOS) for compatibility and security features
- **Emulator Detection**: We detect if the app is running on an emulator to prevent content piracy

### 2.3 Usage Data
- **Course Progress**: Chapters viewed, lectures completed, quiz attempts and scores
- **Video Viewing Data**: Watch time, view counts, and offline view tracking
- **App Interactions**: Features used, content accessed, and time spent
- **Download Activity**: Videos and materials downloaded for offline use

### 2.4 Local Storage Data
The app stores the following locally on your device:
- **Authentication Tokens**: Securely stored using encrypted storage
- **Cached Content**: Courses, chapters, lectures, and comments for offline access
- **User Preferences**: App settings, feature flags, and viewing progress
- **Downloaded Materials**: Encrypted video files and PDF documents

### 2.5 Automatically Collected Technical Data
- **Network Status**: Connectivity information for offline/online mode switching
- **App Version**: For update notifications and feature availability
- **Security Status**: Screen recording/screenshot detection data

## 3. How We Use Your Information

We use the collected information for:

- **Account Management**: Creating and managing your user account
- **Authentication**: Verifying your identity via email or phone OTP
- **Service Provision**: Delivering educational content and course materials
- **Progress Tracking**: Recording your learning progress and achievements
- **Offline Functionality**: Enabling content access without internet connection
- **Security Protection**: Preventing unauthorized content capture (screenshots/screen recording)
- **Live Streaming**: Facilitating real-time educational sessions via WebRTC
- **Content Protection**: Watermarking videos and detecting emulators/rooted devices
- **App Improvement**: Analyzing usage patterns to enhance user experience
- **Notifications**: Sending download progress and course updates
- **Technical Support**: Troubleshooting and resolving issues

## 4. Data Storage and Security

### 4.1 Storage Methods
- **Secure Storage**: Authentication tokens are encrypted using `flutter_secure_storage`
- **Local Database**: App data is stored using Hive database for offline functionality
- **Shared Preferences**: User settings and feature flags
- **Encrypted Downloads**: Video content is encrypted before storage on device

### 4.2 Security Measures
- All network communications use HTTPS encryption
- Downloaded videos are encrypted with unique keys
- Tokens are stored in platform secure storage (Keychain/Keystore)
- Screen capture protection for sensitive content
- Root/jailbreak detection

## 5. Data Sharing and Disclosure

We do not sell, trade, or rent your personal information to third parties. We may share data only in the following circumstances:

- **With Your Educational Institution**: If required for course enrollment verification
- **Service Providers**: Third-party services that help us operate our app (listed below)
- **Legal Requirements**: When required by law or to protect our rights

## 6. Third-Party Services

Our app integrates with the following third-party services:

| Service | Purpose | Data Shared |
|---------|---------|-------------|
| **Learnoo API** | Backend services | All account and usage data |
| **PeerJS Server** (peer.learnoo.app) | Live streaming functionality | Peer connection data, user ID |
| **Google STUN** (stun.l.google.com) | WebRTC connectivity | IP address for connection setup |
| **Device Info Plus** | Device compatibility | Device brand, model, OS version |

## 7. Data Retention

- **Account Data**: Retained while your account is active
- **Local Cache**: Cleared upon logout or app uninstallation
- **Downloaded Content**: Removed when you delete downloads or uninstall the app
- **Pending Actions**: Synced to server when online, then cleared from local queue

## 8. Your Rights

You have the right to:
- **Access**: View your personal information stored in your profile
- **Update**: Modify your account details through the profile settings
- **Delete**: Request account deletion by contacting us
- **Offline Mode**: Access previously downloaded content without internet
- **Opt-out**: Disable certain data collection features (where applicable)

## 9. Children's Privacy

Our service is intended for educational purposes. If you are under 13 years of age (or the applicable age in your jurisdiction), you must have parental consent to use the app. We do not knowingly collect personal information from children under 13 without appropriate consent.

## 10. Permissions Required

The app requests the following permissions:

- **Internet & Network State**: Required for API communication and content streaming
- **Camera**: For capturing profile photos and live streaming participation
- **Microphone**: For audio recording during live sessions and voice features
- **Storage**: For downloading courses, videos, and PDFs for offline access
- **Install Packages**: For app update installation
- **Foreground Service**: For background download operations
- **Package Usage Stats**: For detecting screen recording apps (content protection)

## 11. Live Streaming and WebRTC

When participating in live streaming sessions:
- Your video and audio may be transmitted via WebRTC technology
- Peer connection data is processed through our PeerJS server
- No recordings are stored by us unless explicitly stated

## 12. Content Protection

To protect educational content from unauthorized distribution:
- We detect and prevent screenshots on certain screens
- Screen recording attempts are monitored and may be blocked
- Videos are encrypted when downloaded
- Watermarks may be embedded in video content

## 13. Changes to This Privacy Policy

We may update this Privacy Policy from time to time. We will notify you of any changes by:
- Posting the new policy within the app
- Updating the "Last Updated" date at the top of this policy
- Sending a notification for significant changes

## 14. Contact Us

If you have any questions or concerns about this Privacy Policy or our data practices, please contact us:

**Email:** [Email Address]  
**App Name:** [App Name]

---

## Summary of Data Practices

| Category | Data Type | Purpose |
|----------|-----------|---------|
| **Account** | Name, email, phone | Authentication, identification |
| **Academic** | University, faculty, centers | Course enrollment |
| **Device** | Brand, model, OS | Security, compatibility |
| **Usage** | Progress, views, downloads | Service provision, improvement |
| **Media** | Profile photos | User profiles |
| **Technical** | Tokens, cache, settings | App functionality |

**Firebase Usage:** No Firebase services are used in this application.

**Advertising:** We do not display third-party advertisements or use advertising identifiers.

---

*This Privacy Policy is designed to comply with Google Play Store requirements and applicable privacy regulations.*
