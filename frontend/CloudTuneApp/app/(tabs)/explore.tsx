import { View, Text, StyleSheet } from 'react-native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

export default function ExploreTab() {
  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">В разработке</ThemedText>
      <Text style={styles.descriptionText}>Эта вкладка больше не используется</Text>
      <Text style={styles.developmentText}>Перейдите на вкладки "Локальное" или "Облако"</Text>
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
  descriptionText: {
    fontSize: 16,
    marginTop: 10,
    color: '#888',
    textAlign: 'center',
    marginBottom: 10,
  },
  developmentText: {
    fontSize: 16,
    color: '#666',
    textAlign: 'center',
  },
});
