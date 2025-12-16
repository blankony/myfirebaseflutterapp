![SAPA PNJ Header](SAPA%20PNJ.png)

# SAPA PNJ (Sarana Pengguna Aplikasi Politeknik Negeri Jakarta)

**SAPA PNJ** is a modern, feature-rich social media and communication platform designed exclusively for the Politeknik Negeri Jakarta (PNJ) community. Built with Flutter and backed by a powerful Firebase backend, this application serves as a central hub for students and lecturers to connect, share information, and interact in a dynamic academic environment.

## Project Overview

This project is a comprehensive social platform that integrates advanced **Narrow AI** technologies to enhance user experience. It incorporates a sophisticated multi-step user onboarding process, AI-powered assistance using **Google Gemini**, content safety algorithms, and a real-time notification system. The architecture emphasizes denormalized data for a fast-reading feed, a secure authentication flow restricted to PNJ emails, and a personalized experience through department identification.

## Core Features

### 1. Artificial Intelligence (Narrow AI) Suite
The application leverages various Narrow AI technologies to perform specific intelligent tasks:
- **Generative AI Chatbot (Spirit AI):** An intelligent virtual assistant powered by `Google Gemini 2.5 Flash` capable of answering campus queries, translation, and drafting text with context retention.
- **Visual Detector AI (Content Safety):** An automated image scanning system using AI to detect and block sensitive content (violence, adult content) before upload.
- **Smart Voice Command & TTS:**
  - **Voice Search:** Speech-to-Text integration for hands-free navigation and searching.
  - **Text-to-Speech (TTS):** The assistant can read responses aloud with automatic language detection (ID/EN).
- **Predictive Text Engine:** A custom **Markov Chain** algorithm that learns the user's writing style to suggest the next word while typing.
- **Algorithmic Feed & Trending:** Statistical AI and heuristic algorithms (`N-gram analysis`) to detect trending topics and personalize content discovery based on engagement.

### 2. Trust & Safety System
- **KTM Verification (Blue Badge):** Users can upload their Student ID Card (KTM) to get a "Verified Student" badge, ensuring a trusted ecosystem.
- **Bad Word Guard:** Real-time text filtering system that prevents the posting of offensive language or hate speech.
- **Moderation Tools:** Comprehensive reporting system and user blocking capabilities to maintain a healthy community.

### 3. Community Hub & Management
- **Community Groups:** Dedicated spaces for Student Activity Units (UKM) or Departments.
- **Role-Based Access:** Support for **Admins** and **Editors** to manage community pages.
- **Official Broadcasts:** "Post as Community" feature allowing admins to publish official announcements under the organization's identity.

### 4. Social & Real-time Interaction
- **Rich Media Posting:** Support for image cropping and video trimming/compression.
- **Draft System:** Save posts locally to finish editing later.
- **Privacy Controls:** Set post visibility to Public, Followers Only, or Private.
- **Social Graph:** Connect with friends via Follow/Unfollow system and "Friends of Friends" recommendations.

### 5. Authentication & Onboarding
- **Exclusive Registration:** Restricted to official PNJ student emails (`@stu.pnj.ac.id`).
- **Secure Auth:** Full support for login, registration, and password reset via Firebase Auth.
- **Guided Setup:** Multi-step onboarding for profile and academic data setup.

### 6. Media & Optimization
- **Cloudinary Integration:** Offloads media storage to Cloudinary for optimized delivery and reduced server load.
- **Offline Capabilities:** Local caching using Shared Preferences for settings and basic data.

## Screenshots

Here is a sneak peek of the application. For the complete list of all 47 screenshots covering every feature, please visit the **[Screenshot Gallery](gallery.md)**.

| Home Feed | Community | AI Assistant | User Profile |
|---|---|---|---|
| <img src="screenshots/home.jpg" width="200"/> | <img src="screenshots/community_view.jpg" width="200"/> | <img src="screenshots/spirit_ai.jpg" width="200"/> | <img src="screenshots/profile_posts.jpg" width="200"/> |

**[Click here to view the full Screenshot Gallery](gallery.md)**

---

## Getting Started

Firebase and API key configuration is required before running the application.

### 1. Firebase Project Setup
- **Create a Firebase Project:** Go to the [Firebase Console](https://console.firebase.google.com/) and create a new project.
- **Add FlutterApp:** Follow the setup guide to connect your Flutter application.
- **Enable Services:**
  - **Authentication:** Enable the `Email/Password` sign-in provider.
  - **Firestore:** Create a Firestore database and use the security rules below.

### 2. Firestore Security Rules
Copy and paste the following rules into your Firestore rules editor:
```json
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {

    // --- HELPER FUNCTIONS ---
    function isAuthenticated() {
      return request.auth != null;
    }

    function isOwner(userId) {
      return isAuthenticated() && request.auth.uid == userId;
    }

    function isResourceOwner() {
      return isAuthenticated() && resource.data.userId == request.auth.uid;
    }

    // Cek Admin Komunitas
    function isCommunityAdmin(communityId) {
       return communityId != null && 
              exists(/databases/$(database)/documents/communities/$(communityId)) &&
              get(/databases/$(database)/documents/communities/$(communityId)).data.admins.hasAny([request.auth.uid]);
    }

    // 1. USERS
    match /users/{userId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated() && request.auth.uid == userId;
      allow delete: if isOwner(userId);
      allow update: if isAuthenticated() && (
        isOwner(userId) || 
        (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followers', 'following', 'isPrivate']))
      );
      match /bookmarks/{document=**} { allow read, write: if isOwner(userId); }
      match /notifications/{notificationId} { 
        allow create: if isAuthenticated();
        allow update: if isOwner(userId);
        allow get: if isOwner(userId) || (isAuthenticated() && resource.data.senderId == request.auth.uid);
        allow list: if isOwner(userId) || (isAuthenticated() && resource.data.senderId == request.auth.uid);
        allow delete: if isOwner(userId) || (isAuthenticated() && resource.data.senderId == request.auth.uid);
      }
      match /chat_sessions/{document=**} { allow read, write: if isOwner(userId); }
      match /follow_requests/{requesterId} {
        allow read: if isAuthenticated() && (request.auth.uid == userId || request.auth.uid == requesterId);
        allow create: if isAuthenticated() && request.auth.uid == requesterId;
        allow delete: if isAuthenticated() && (request.auth.uid == userId || request.auth.uid == requesterId);
      }
    }

    // 2. COMMUNITIES
    match /communities/{communityId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      // Izinkan update (join/leave/edit info/upload image/manage roles)
      allow update: if isAuthenticated(); 
      // Izinkan DELETE hanya jika user adalah Owner
      allow delete: if isAuthenticated() && resource.data.ownerId == request.auth.uid;
    }

    // 3. POSTS
    match /posts/{postId} {
      allow read: if isAuthenticated();
      allow create: if isAuthenticated();
      allow delete: if isAuthenticated() && (
        resource.data.userId == request.auth.uid || 
        isCommunityAdmin(resource.data.communityId)
      );
      allow update: if isAuthenticated() && (
        (isResourceOwner() && 
          request.resource.data.diff(resource.data).affectedKeys().hasOnly([
            'text', 'userName', 'avatarIconId', 'avatarHex', 'profileImageUrl', 
            'mediaUrl', 'mediaType', 'isUploading', 'uploadProgress', 'uploadFailed',
            'editedAt', 'visibility', 'communityId'
          ])) ||
        (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes', 'commentCount', 'repostedBy']))
      );
      match /comments/{commentId} {
        allow read: if isAuthenticated();
        allow create: if isAuthenticated();
        allow delete: if isAuthenticated() && (
           resource.data.userId == request.auth.uid ||
           isCommunityAdmin(get(/databases/$(database)/documents/posts/$(postId)).data.communityId)
        );
        allow update: if isAuthenticated() && (
          (isResourceOwner() && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['text', 'userName', 'avatarIconId', 'avatarHex', 'profileImageUrl'])) ||
          (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes', 'repostedBy']))
        );
      }
    }

    // 4. REPORTS
    match /reports/{reportId} {
      allow create: if isAuthenticated();
      allow read: if false; 
    }
    
    // 5. COLLECTION GROUP
    match /{path=**}/comments/{commentId} {
      allow read: if isAuthenticated();
    }
  }
}
```

### 3. Environment Configuration (.env)
This project uses flutter_dotenv to securely manage API keys. You must create a .env file in the root directory of the project to enable AI features (Spirit AI, Content Guard) and Media Uploads.
  1. Create a file named .env in the root of your project folder.
  2. Copy and paste the keys below, replacing the values with your own API keys:

```.env
# Google AI Studio Key (for Spirit AI & Content Safety)
GEMINI_API_KEY=your_google_gemini_api_key

# Cloudinary Config (for Image/Video Uploads)
CLOUDINARY_CLOUD_NAME=your_cloudinary_cloud_name
CLOUDINARY_UPLOAD_PRESET=your_cloudinary_upload_preset

# Optional: Required for deleting/moderating media from the app
CLOUDINARY_API_KEY=your_cloudinary_api_key
CLOUDINARY_API_SECRET=your_cloudinary_api_secret
```
