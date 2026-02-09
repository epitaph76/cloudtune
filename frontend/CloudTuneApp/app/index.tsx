// app/index.tsx - SplashScreen
import React, { useEffect } from 'react';
import { View, Text, StyleSheet, Image } from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/providers/AuthProvider';

export default function SplashScreen() {
  const router = useRouter();
  const { loading, isAuthenticated } = useAuth();

  useEffect(() => {
    // Имитация загрузки, затем переход к соответствующему экрану
    const timer = setTimeout(() => {
      if (isAuthenticated) {
        router.replace('/(tabs)/'); // Переход к вкладкам, если пользователь аутентифицирован
      } else {
        router.replace('/auth'); // Переход к экрану аутентификации
      }
    }, 2000); // 2 секунды на SplashScreen

    return () => clearTimeout(timer);
  }, [isAuthenticated, router]);

  if (loading) {
    return (
      <View style={styles.container}>
        <Text>Загрузка...</Text>
      </View>
    );
  }

  return (
    <View style={styles.container}>
      <Image 
        source={require('@/assets/images/icon.png')} // Используем стандартный иконку Expo
        style={styles.logo}
        resizeMode="contain"
      />
      <Text style={styles.title}>CloudTune</Text>
      <Text style={styles.subtitle}>Upload your music library and stream everywhere</Text>
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    backgroundColor: '#ffffff',
  },
  logo: {
    width: 150,
    height: 150,
    marginBottom: 30,
  },
  title: {
    fontSize: 32,
    fontWeight: 'bold',
    textAlign: 'center',
    color: '#333',
    marginBottom: 10,
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
    color: '#666',
  },
});