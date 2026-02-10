import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, FlatList, Alert } from 'react-native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

// Заглушка для типа файла
interface AudioFile {
  id: string;
  name: string;
  size: number;
  duration?: string;
}

export default function LocalStorageScreen() {
  const [audioFiles, setAudioFiles] = useState<AudioFile[]>([]);
  const [loading, setLoading] = useState(false);

  const pickAudioFile = async () => {
    setLoading(true);
    try {
      // В реальном приложении здесь будет вызов expo-document-picker
      // Для демонстрации добавим заглушку
      const mockFile: AudioFile = {
        id: Date.now().toString(),
        name: `demo-track-${audioFiles.length + 1}.mp3`,
        size: Math.floor(Math.random() * 10000000) + 5000000, // 5-15 MB
      };
      
      setAudioFiles(prev => [...prev, mockFile]);
      Alert.alert('Успех', 'Файл добавлен (демонстрация)');
    } catch (error) {
      console.error('Ошибка при выборе файла:', error);
      Alert.alert('Ошибка', 'Не удалось выбрать файл');
    } finally {
      setLoading(false);
    }
  };

  const formatFileSize = (bytes: number): string => {
    if (bytes < 1024) return bytes + ' B';
    else if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
    else return (bytes / 1048576).toFixed(1) + ' MB';
  };

  const renderFileItem = ({ item }: { item: AudioFile }) => (
    <View style={styles.fileItem}>
      <View style={styles.fileInfo}>
        <Text style={styles.fileName} numberOfLines={1}>{item.name}</Text>
        <Text style={styles.fileSize}>{formatFileSize(item.size)}</Text>
      </View>
    </View>
  );

  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">Local Storage</ThemedText>
      <Text style={styles.descriptionText}>Файлы на вашем устройстве</Text>
      
      <TouchableOpacity 
        style={[styles.addButton, loading && styles.addButtonDisabled]} 
        onPress={pickAudioFile}
        disabled={loading}
      >
        <ThemedText type="buttonText">
          {loading ? 'Загрузка...' : 'Добавить файл'}
        </ThemedText>
      </TouchableOpacity>
      
      <View style={styles.filesSection}>
        <ThemedText type="subtitle" style={styles.sectionTitle}>
          Мои треки ({audioFiles.length})
        </ThemedText>
        
        {audioFiles.length > 0 ? (
          <FlatList
            data={audioFiles}
            renderItem={renderFileItem}
            keyExtractor={(item) => item.id}
            style={styles.filesList}
          />
        ) : (
          <Text style={styles.emptyStateText}>Пока нет добавленных файлов</Text>
        )}
      </View>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
  },
  descriptionText: {
    fontSize: 16,
    marginTop: 10,
    color: '#888',
    textAlign: 'center',
    marginBottom: 20,
  },
  addButton: {
    backgroundColor: '#4CAF50',
    paddingVertical: 12,
    paddingHorizontal: 20,
    borderRadius: 8,
    alignItems: 'center',
    marginVertical: 15,
  },
  addButtonDisabled: {
    backgroundColor: '#cccccc',
  },
  filesSection: {
    flex: 1,
    width: '100%',
  },
  sectionTitle: {
    fontSize: 18,
    marginBottom: 15,
    color: '#333',
  },
  filesList: {
    flex: 1,
  },
  fileItem: {
    flexDirection: 'row',
    justifyContent: 'space-between',
    alignItems: 'center',
    padding: 15,
    backgroundColor: '#f5f5f5',
    borderRadius: 8,
    marginBottom: 10,
  },
  fileInfo: {
    flex: 1,
  },
  fileName: {
    fontSize: 16,
    fontWeight: '500',
    color: '#333',
  },
  fileSize: {
    fontSize: 14,
    color: '#666',
    marginTop: 5,
  },
  emptyStateText: {
    textAlign: 'center',
    color: '#999',
    fontStyle: 'italic',
    marginTop: 30,
  },
});