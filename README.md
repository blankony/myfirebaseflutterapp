![SAPA PNJ Header](SAPA%20PNJ.png)

# SAPA PNJ (Sarana Pengguna Aplikasi Politeknik Negeri Jakarta)

**SAPA PNJ** is a modern, feature-rich social media and communication platform designed exclusively for the Politeknik Negeri Jakarta (PNJ) community. Built with Flutter and backed by a powerful Firebase backend, this application serves as a central hub for students and lecturers to connect, share information, and interact in a dynamic academic environment.

## Project Overview

This project is a comprehensive social platform that integrates advanced **Narrow AI** technologies to enhance user experience. It incorporates a sophisticated multi-step user onboarding process, AI-powered assistance using **Google Gemini**, content safety algorithms, and a real-time notification system. The architecture emphasizes denormalized data for a fast-reading feed, a secure authentication flow restricted to PNJ emails, and a personalized experience through department identification.

## Core Features

### 1. Artificial Intelligence Suite
The application leverages various Narrow AI technologies to perform specific intelligent tasks:
- **Generative AI Chatbot (Spirit AI):** An intelligent virtual assistant powered by `Google Gemini 2.5 Flash` capable of answering campus queries, translation, and drafting text with context retention.
- **Visual Detector AI (Content Safety):** An automated image scanning system using AI to detect and block sensitive content (violence, adult content) before upload.
- **Smart Voice Command & TTS:**
  - **Voice Search:** Speech-to-Text integration for hands-free navigation and searching.
  - **Text-to-Speech (TTS):** The assistant can read responses aloud with automatic language detection (ID/EN).
- **Predictive Text Engine:** A custom **Markov Chain** algorithm that learns the user's writing style to suggest the next word while typing.
- **Algorithmic Feed & Trending:** Statistical AI and heuristic algorithms (`N-gram analysis`) to detect trending topics and personalize content discovery based on engagement.

### 2. Trust & Safety System
- **KTM Verification (Blue Badge Checkmark):** Users can upload their Student ID Card (KTM) to get a "Verified Student" badge, ensuring a trusted ecosystem.
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

👉 **[Click here to view the full Screenshot Gallery (GALLERY.md)](gallery.md)**

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
```txt
rules_version = '2';
service cloud.firestore {
  match /databases/{database}/documents {
    
    // USERS: Allow user to update their own profile fields
    match /users/{userId} {
      allow read, create: if request.auth.uid != null;
      allow delete: if request.auth.uid == userId;
      
      allow update: if request.auth.uid != null && (
        (request.auth.uid == userId) || // User updates own profile
        (request.auth.uid != userId && 
         request.resource.data.diff(resource.data).affectedKeys().hasOnly(['followers'])) // Other user follows
      );
    }

    // NOTIFICATIONS
    match /users/{userId}/notifications/{notificationId} {
      allow create: if request.auth.uid != null;
      allow read, update, delete: if request.auth.uid == userId;
    }

    // POSTS: Allow updating avatar fields on own posts
    match /posts/{postId} {
      allow read, create: if request.auth != null;
      allow delete: if request.auth.uid == resource.data.userId;

      allow update: if request.auth != null && (
        // Allow updating profile info on old posts
        (request.auth.uid == resource.data.userId && 
         request.resource.data.diff(resource.data).affectedKeys().hasOnly(['text', 'userName', 'avatarIconId', 'avatarHex'])) ||
        
        // Allow updating likes/comments count by others
        (request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes', 'commentCount', 'repostedBy']))
      );
    }

    // COMMENTS: Allow updating avatar fields on own comments
    match /posts/{postId}/comments/{commentId} {
      allow read, create: if request.auth != null;
      allow delete: if request.auth.uid == resource.data.userId;
      
      allow update: if request.auth.uid == resource.data.userId && (
        request.resource.data.diff(resource.data).affectedKeys().hasOnly(['text', 'userName', 'avatarIconId', 'avatarHex'])
      );
    }
    
    match /{path=**}/comments/{commentId} {
      allow read: if request.auth != null;
    }
  }
}