```md
# PNJ Media App

A Flutter-based social platform for the PNJ community. Backed entirely by Firebase for authentication, Firestore, and security rules. Styled with a modern dark-first interface.

## Core Features

- Firebase Authentication with login, register, and password recovery  
- Persistent sessions  
- Optional email verification  
- Real-time Firestore backend  
- Full CRUD for posts and replies  
- Post interactions (like/unlike)  
- Live feed sorted by timestamp  
- User profiles with bio, name, NIM, and email  
- Individual profile navigation  
- Light/Dark theme toggle  
- Profile editing and password change  
- Logout and account deletion  

## Screenshots

> Add your images to `./screenshots/` and replace the placeholders below.

### Landing & Auth
![Landing](screenshots/landing.png)
![Login](screenshots/login.png)
![Register](screenshots/register.png)

### Home & Profile
![Home](screenshots/home.png)
![Profile](screenshots/profile.png)

### Posting & Interacting
![Post](screenshots/post.png)
![Reply](screenshots/reply.png)
![Like](screenshots/repost_like.png)

### Edit Profile
![Edit Profile](screenshots/edit_profile.png)

---

## Getting Started

Firebase configuration is required before running the application.

---

## 1. Firebase Project Setup

### Create a Firebase Project  
- Create a new project in the Firebase Console.

### Add Android App  
- Package name: `com.example.myfirebaseflutterapp`  
- Obtain SHA-1:  
```

./gradlew signingReport

````
- Add SHA-1 to Firebase.  
- Download `google-services.json` into `android/app/`.

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
````

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

