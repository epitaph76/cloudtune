// app/(tabs)/cloud.tsx
import { View, Text, StyleSheet } from 'react-native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

export default function CloudTab() {
  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">Cloud Storage</ThemedText>
      <Text style={styles.developmentText}>Облачные файлы</Text>
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