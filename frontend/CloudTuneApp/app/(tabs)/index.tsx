// app/(tabs)/index.tsx
import React, { useState, useEffect } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, FlatList, Alert } from 'react-native';
import AsyncStorage from '@react-native-async-storage/async-storage';
import { useFocusEffect } from '@react-navigation/native';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';
import { audioPlayerService } from '@/lib/trackPlayerService';

// Тип для аудиофайла
interface AudioFile {
  id: string;
  name: string;
  size: number;
  uri: string;
  duration?: string;
  artist?: string; // Добавляем поле для исполнителя
}

const LOCAL_FILES_STORAGE_KEY = 'local_audio_files';

export default function HomeTab() {
  const [audioFiles, setAudioFiles] = useState<AudioFile[]>([]);
  const [playingFile, setPlayingFile] = useState<string | null>(null);

  // Загружаем все файлы при монтировании компонента
  useEffect(() => {
    // Подписываемся на обновления состояния воспроизведения
    const interval = setInterval(async () => {
      try {
        const currentTrack = await audioPlayerService.getCurrentTrack();
        const state = await audioPlayerService.getPlaybackState();
        
        if (currentTrack && (state.state === State.Playing)) {
          // Найти ID файла по ID трека
          const currentFile = audioFiles.find(file => file.id === currentTrack.id);
          if (currentFile) {
            setPlayingFile(currentFile.id);
          }
        } else {
          setPlayingFile(null);
        }
      } catch (error) {
        console.error('Ошибка при получении состояния воспроизведения:', error);
        setPlayingFile(null);
      }
    }, 1000); // Обновляем каждую секунду

    return () => {
      clearInterval(interval);
    };
  }, [audioFiles]);

  // Обновляем список файлов при фокусе на вкладке
  useFocusEffect(
    React.useCallback(() => {
      loadAllFiles();
    }, [])
  );

  const loadAllFiles = async () => {
    try {
      const savedFiles = await AsyncStorage.getItem(LOCAL_FILES_STORAGE_KEY);
      if (savedFiles) {
        setAudioFiles(JSON.parse(savedFiles));
      } else {
        setAudioFiles([]);
      }
    } catch (error) {
      console.error('Ошибка при загрузке файлов:', error);
    }
  };

  const togglePlayback = async (fileId: string, uri: string, trackName: string = 'Неизвестный трек', artist: string = 'CloudTune') => {
    if (playingFile === fileId) {
      // Пауза текущего трека
      await audioPlayerService.pause();
      setPlayingFile(null);
    } else {
      // Воспроизведение нового трека
      try {
        // Добавляем трек в очередь и воспроизводим его
        await audioPlayerService.addTrack({
          id: fileId,
          url: uri,
          title: trackName,
          artist: artist
        });
        await audioPlayerService.playTrack(fileId);
        setPlayingFile(fileId);
      } catch (error) {
        console.error('Ошибка при воспроизведении аудио:', error);
        Alert.alert('Ошибка', 'Не удалось воспроизвести аудиофайл');
      }
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
      <TouchableOpacity
        style={styles.playButton}
        onPress={() => togglePlayback(item.id, item.uri, item.name, item.artist || 'CloudTune')}
      >
        <Text style={styles.playButtonText}>
          {playingFile === item.id ? '⏹' : '▶'}
        </Text>
      </TouchableOpacity>
    </View>
  );

  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">CloudTune</ThemedText>
      <Text style={styles.descriptionText}>Ваш личный облачный плеер музыки</Text>

      <View style={styles.filesSection}>
        <ThemedText type="subtitle" style={styles.sectionTitle}>
          Все треки ({audioFiles.length})
        </ThemedText>

        {audioFiles.length > 0 ? (
          <FlatList
            data={audioFiles}
            renderItem={renderFileItem}
            keyExtractor={(item) => item.id}
            style={styles.filesList}
          />
        ) : (
          <Text style={styles.emptyStateText}>Нет доступных треков</Text>
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
  playButton: {
    backgroundColor: '#4CAF50',
    width: 40,
    height: 40,
    borderRadius: 20,
    justifyContent: 'center',
    alignItems: 'center',
    marginLeft: 10,
  },
  playButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
  emptyStateText: {
    textAlign: 'center',
    color: '#999',
    fontStyle: 'italic',
    marginTop: 30,
  },
});