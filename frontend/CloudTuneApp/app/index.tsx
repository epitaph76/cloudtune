// app/index.tsx
import { View, Text, StyleSheet } from 'react-native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

export default function HomeScreen() {
  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">CloudTune</ThemedText>
      <Text style={styles.developmentText}>Добро пожаловать в CloudTune!</Text>
      <Text style={styles.developmentText}>В разработке</Text>
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