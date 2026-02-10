// app/index.tsx
import { useEffect } from 'react';
import { View, Text, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';
import { useAuth } from '@/providers/AuthProvider';

export default function HomeScreen() {
  const router = useRouter();
  const { isAuthenticated } = useAuth();

  useEffect(() => {
    // Перенаправляем на вкладки сразу
    const timer = setTimeout(() => {
      router.replace('/(tabs)');
    }, 1000); // Небольшая задержка для лучшего UX

    return () => clearTimeout(timer);
  }, [router]);

  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">CloudTune</ThemedText>
      <Text style={styles.developmentText}>Загрузка...</Text>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  developmentText: {
    fontSize: 18,
    marginTop: 20,
    color: '#666',
    textAlign: 'center',
  },
});