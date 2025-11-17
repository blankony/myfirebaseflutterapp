# PNJ Media App

A Flutter-based social platform for the PNJ community. Backed by Firebase for authentication, Firestore, and security rules. Built with a dark-first UI.

## Core Features

- Firebase Authentication (login, register, password reset)  
- Persistent sessions  
- Optional email verification  
- Real-time Firestore backend  
- Full CRUD for posts and replies  
- Like/Unlike, Repost, Follow/Unfollow interactions
- Live feed sorted by timestamp  
- User profiles with bio, name, NIM, email  
- Profile navigation  
- Light/Dark theme toggle  
- Profile editing and password change  
- Logout and account deletion  

## Screenshots
### Landing & Auth
| Landing | Login | Register |
|--------|--------|----------|
| <img src="screenshots/landing.png" width="250"/> | <img src="screenshots/login.png" width="250"/> | <img src="screenshots/register.png" width="250"/> |

### Home & Profile
| Home | Profile | Others Profile |
|------|--------|-----------------|
| <img src="screenshots/home.png" width="250"/> | <img src="screenshots/profile.png" width="250"/> | <img src="screenshots/others.png" width="250"/> |

### Posting & Interacting
| Post | Reply | Like |
|------|--------|------|
| <img src="screenshots/post.png" width="250"/> | <img src="screenshots/reply.png" width="250"/> | <img src="screenshots/repost_like.png" width="250"/> |

### Settings
| Settings | Edit Profile | About |
|----------|--------------|-------|
| <img src="screenshots/settings.png" width="250"/> | <img src="screenshots/edit_profile.png" width="250"/> | <img src="screenshots/about.png" width="250"/> |

---

## Getting Started

Firebase configuration is required before running the application.

---

## 1. Firebase Project Setup

### Create a Firebase Project
- Create a new project in the Firebase Console.

### Add Android App
- Package name: `com.example.myfirebaseflutterapp`  
- Place `google-services.json` inside `android/app/`.

### Enable Services
- Authentication → Enable Email/Password  
- Firestore → Create database  

### Firestore Security Rules
```txt
rules_version = '2';
service cloud.firestore {
match /databases/{database}/documents {

  match /users/{userId} {
    allow read, create, update: if request.auth != null && request.auth.uid == userId;
  }

  match /posts/{postId} {
    allow read, create: if request.auth != null;
    allow delete: if request.auth != null && resource.data.userId == request.auth.uid;

    allow update: if request.auth != null && (
      (resource.data.userId == request.auth.uid &&
       request.resource.data.diff(resource.data).affectedKeys().hasOnly(['text'])) ||
      request.resource.data.diff(resource.data).affectedKeys().hasOnly(['likes']) ||
      request.resource.data.diff(resource.data).affectedKeys().hasOnly(['commentCount'])
    );

    match /comments/{commentId} {
      allow read, create: if request.auth != null;
      allow update, delete: if request.auth != null && resource.data.userId == request.auth.uid;
    }
  }

  match /{path=**}/comments/{commentId} {
    allow read: if request.auth != null;
  }
}
}
```
### Firestore Indexes

**Posts Tab (Collection):**

* Collection ID: `posts`
* `userId` Ascending
* `timestamp` Descending

**Replies Tab (Collection Group):**

* Collection ID: `comments`
* `userId` Ascending
* `timestamp` Descending

---

## 2. Local Setup

Clone:

```sh
git clone https://github.com/blankony/myfirebaseflutterapp
```

Install:

```sh
flutter pub get
```

Run:

```sh
flutter run
```

---

## Main Dependencies

* `firebase_core`
* `firebase_auth`
* `cloud_firestore`
* `timeago`

