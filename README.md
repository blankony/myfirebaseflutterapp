![SAPA PNJ Header](SAPA%20PNJ.png)

# SAPA PNJ (Sarana Pengguna Aplikasi Politeknik Negeri Jakarta)

**SAPA PNJ** is a modern, feature-rich social media and communication platform designed exclusively for the Politeknik Negeri Jakarta (PNJ) community. Built with Flutter and backed by a powerful Firebase backend, this application serves as a central hub for students and lecturers to connect, share information, and interact in a dynamic academic environment.

## Project Overview

This project is a comprehensive social platform that goes beyond basic posting and liking. It incorporates a sophisticated, multi-step user onboarding process, AI-powered assistance using **Google Gemini**, rich media handling with **Cloudinary**, and a real-time notification system. The user interface is designed to be intuitive and clean, with support for both light and dark themes, ensuring a great user experience.

The architecture emphasizes denormalized data for a fast-reading feed, a secure authentication flow restricted to PNJ emails, and a personalized experience through department/study program identification.

## Core Features

### 1. Authentication & Onboarding
- **Exclusive Registration:** User registration is restricted to official PNJ student emails (`@stu.pnj.ac.id`), ensuring the community remains exclusive.
- **Complete Auth Suite:** Full support for login, registration, and password reset.
- **Guided Setup Flow:** A multi-step onboarding process for new users including profile setup and academic info verification.

### 2. Social & Real-time Interaction
- **Real-time Feed:** A live home feed showing the latest posts from the community.
- **Community Groups:** Join and interact within specific communities.
- **Social Actions:** Users can **Like**, **Repost**, and **Comment** on posts.

### 3. AI-Powered Features (Google Gemini)
- **AI Assistant:** A dedicated, conversational AI assistant powered by `gemini-1.5-flash` to answer questions and provide help.
- **Predictive Text:** AI-powered text completion suggests relevant words while creating posts.

### 4. Media Handling
- **Image & Video Uploads:** Users can attach images and videos to posts.
- **Cloudinary Integration:** Optimized media storage and delivery.
- **Built-in Editor:** Integrated tools to crop images and trim videos.

### 5. Profiles & Account Management
- **Detailed Profiles:** Showcases user info, posts, replies, and reposts.
- **Account Control:** Full settings to manage password, blocked users, and privacy.

## Screenshots

Here is a sneak peek of the application. For the complete list of all 47 screenshots covering every feature, please visit the **[Screenshot Gallery](GALLERY.md)**.

| Home Feed | Community | AI Assistant | User Profile |
|---|---|---|---|
| <img src="screenshots/home.jpg" width="200"/> | <img src="screenshots/community_view.jpg" width="200"/> | <img src="screenshots/spirit_ai.jpg" width="200"/> | <img src="screenshots/profile_posts.jpg" width="200"/> |

👉 **[Click here to view the full Screenshot Gallery (GALLERY.md)](GALLERY.md)**

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