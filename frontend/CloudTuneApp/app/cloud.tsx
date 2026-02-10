import { View, Text, StyleSheet } from 'react-native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

export default function CloudTab() {
  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">Cloud Storage</ThemedText>
      <Text style={styles.descriptionText}>Файлы пользователя на сервере</Text>
      <Text style={styles.developmentText}>Здесь будут отображаться ваши музыкальные файлы</Text>
      <Text style={styles.developmentText}>и плейлисты, хранящиеся в облаке</Text>
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
  descriptionText: {
    fontSize: 18,
    marginTop: 10,
    color: '#888',
    textAlign: 'center',
    marginBottom: 20,
  },
  developmentText: {
    fontSize: 16,
    marginTop: 10,
    color: '#666',
    textAlign: 'center',
  },
});