# CloudTune Frontend

The React Native/Expo frontend for CloudTune - a cloud music player application with cross-device synchronization.

## 🎵 About

CloudTune Frontend is a mobile application built with React Native and Expo that provides a seamless music listening experience across devices. The app connects to the CloudTune backend to manage user accounts, playlists, and music collections. The application supports local audio file playback with background audio capabilities.

## 🛠 Technologies

- **React Native** - cross-platform mobile development
- **Expo** - development workflow and services
- **TypeScript** - type-safe JavaScript
- **React Navigation** - navigation solution
- **Async Storage** - local data persistence
- **Expo Router** - file-based routing
- **Expo Audio** - audio playback capabilities
- **Expo AV** - audio/video handling

## 📁 Project Structure

```
frontend/CloudTuneApp/
├── app/                    # Application screens and routes
│   ├── (tabs)/           # Tab navigator screens
│   │   ├── _layout.tsx   # Tab navigator layout
│   │   ├── index.tsx     # Main screen with audio playback
│   │   ├── local.tsx     # Local storage screen
│   │   ├── profile.tsx   # Profile screen with authentication
│   │   └── cloud.tsx     # Cloud storage screen
│   ├── _layout.tsx       # Root layout with providers
│   ├── index.tsx         # Splash screen with logo
│   ├── login.tsx         # Login screen
│   ├── register.tsx      # Registration screen
│   └── modal.tsx         # Modal screen example
├── components/            # Reusable UI components
├── constants/             # Constants and themes
│   └── theme.ts          # Color and font themes
├── contexts/              # React contexts
├── hooks/                 # Custom React hooks
├── lib/                   # Utility functions and API calls
│   ├── api.ts            # API client and endpoints
│   └── authStorage.ts    # Authentication token storage
├── providers/             # React providers
│   └── AuthProvider.tsx  # Authentication context provider
├── assets/                # Static assets (images, icons)
├── node_modules/          # Dependencies
├── package.json          # Project dependencies and scripts
├── app.json              # Expo configuration
├── tsconfig.json         # TypeScript configuration
└── ...
```

## 🚀 Getting Started

### Prerequisites

- Node.js (v18 or later)
- npm or yarn
- Expo Go app installed on your mobile device (for testing)

### Installation

1. Navigate to the frontend directory:
   ```bash
   cd frontend/CloudTuneApp
   ```

2. Install dependencies:
   ```bash
   npm install
   ```

3. Start the development server:
   ```bash
   npx expo start
   ```

4. Scan the QR code with the Expo Go app on your mobile device or use an emulator

### Development Scripts

- `npm start` - start the development server
- `npm run android` - open the app in an Android emulator
- `npm run ios` - open the app in an iOS simulator
- `npm run web` - open the app in a web browser
- `npm run reset-project` - reset the project to initial state

## 🎧 Audio Playback Features

The application includes local audio file playback functionality:

- **Audio File Selection**: Users can select audio files from their device using Document Picker
- **Local Storage**: Selected audio files are stored locally using Async Storage
- **Audio Playback**: Uses Expo Audio for playing audio files with play/pause controls
- **Background Audio**: Audio continues playing when the app is in the background (iOS/Android)
- **Supported Formats**: MP3, WAV, M4A, FLAC and other common audio formats

### Audio Playback Implementation

The audio playback is implemented using `expo-audio` library:
- Main playback functionality is in `app/(tabs)/index.tsx`
- Audio files are selected and stored in `app/(tabs)/local.tsx`
- The `AudioPlayer` class manages playback state and controls

## 🌐 API Integration

The frontend communicates with the CloudTune backend API for user authentication and data management. The API client is located in `lib/api.ts` and includes:

- User registration
- User login
- Profile retrieval
- Token management

Make sure the backend is running and accessible at the configured URL before testing authentication features.

## 🎨 Theming

The application supports both light and dark modes. The theme configuration is located in `constants/theme.ts` and includes:

- Color palettes for both light and dark modes
- Font configurations for different platforms
- Consistent styling across the application

## 🔐 Authentication Flow

The application implements a secure authentication flow:

1. User registration/login on the landing screen
2. JWT token storage in Async Storage
3. Automatic authentication state management
4. Protected routes that require authentication
5. Logout functionality

The authentication context is managed by `AuthProvider.tsx` which handles token storage and user state.

## 🧪 Testing

To run tests:
```bash
npm test
```

## 🚢 Deployment

To build the application for production:

1. Create a production build:
   ```bash
   npx expo export
   ```

2. For app stores, follow the Expo documentation for building standalone apps:
   - [Building Standalone Apps](https://docs.expo.dev/distribution/building-standalone-apps/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Make your changes
4. Commit your changes (`git commit -m 'Add amazing feature'`)
5. Push to the branch (`git push origin feature/amazing-feature`)
6. Open a Pull Request

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](../../LICENSE) file for details.

## 🐞 Troubleshooting

### Common Issues

1. **Network requests failing**: Ensure the backend API URL in `lib/api.ts` is correctly configured and accessible from your device/emulator.

2. **Expo Go connection issues**: Make sure your computer and mobile device are on the same network when testing on a physical device.

3. **TypeScript errors**: Run `npx tsc --noEmit` to check for TypeScript compilation errors.

4. **Audio playback issues**: Check that the app has necessary permissions to access media files and play audio in the background.

### Debugging Tips

- Enable Remote Debugging in Expo Go for browser-based debugging
- Use React Native Debugger for enhanced debugging experience
- Check the Metro Bundler logs for any build errors
- Verify that the backend service is running and accessible

## 🌟 Features

- Responsive UI that works on various screen sizes
- Light and dark theme support
- Secure authentication with JWT tokens
- Cross-platform compatibility (iOS/Android)
- Offline token storage
- Local audio file selection and playback
- Background audio playback support
- Clean, modern UI design
- Proper error handling and user feedback
