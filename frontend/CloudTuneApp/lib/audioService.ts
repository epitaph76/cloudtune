import { Audio, InterruptionModeAndroid, InterruptionModeIOS } from 'expo-av';
import { Platform } from 'react-native';
import { 
  initializeNotificationService, 
  createPlaybackNotification, 
  updatePlaybackNotification,
  dismissActiveNotification,
  getActiveNotificationId
} from './notificationService';

// Инициализация аудио режима для фоновой работы
export const initializeAudioService = async () => {
  try {
    // Настройка аудио режима для фоновой работы
    await Audio.setAudioModeAsync({
      playsInSilentModeIOS: true, // Воспроизведение в silent режиме на iOS
      staysActiveInBackground: true, // Оставаться активным в фоне
      shouldDuckAndroid: true, // Уменьшать громкость других источников на Android
      interruptionModeIOS: InterruptionModeIOS.MixWithOthers, // Режим прерывания на iOS
      interruptionModeAndroid: InterruptionModeAndroid.DuckOthers, // Режим прерывания на Android
      playThroughEarpieceAndroid: false, // Воспроизводить через динамик на Android
    });

    // Инициализация сервиса уведомлений
    await initializeNotificationService();
  } catch (error) {
    console.error('Ошибка при инициализации аудио сервиса:', error);
  }
};

// Класс для управления воспроизведением аудио
class AudioPlayerService {
  private soundObject: Audio.Sound | null = null;
  private currentTrackUri: string | null = null;
  private currentTrackName: string = '';
  private currentArtist: string = 'CloudTune';
  private isPlaying: boolean = false;

  constructor() {
    this.initialize();
  }

  private async initialize() {
    await initializeAudioService();

    // Устанавливаем глобальные обработчики для уведомлений
    global.handleTogglePlayback = () => {
      if (this.isPlaying) {
        this.pause();
      } else {
        this.play();
      }
    };

    global.handleNextTrack = () => {
      // Здесь будет логика для следующего трека
      console.log('Следующий трек');
    };

    global.handlePreviousTrack = () => {
      // Здесь будет логика для предыдущего трека
      console.log('Предыдущий трек');
    };
  }

  async loadAndPlay(uri: string, trackName: string = 'Неизвестный трек', artist: string = 'CloudTune') {
    try {
      // Если уже воспроизводится другой трек, остановим его
      if (this.soundObject && this.currentTrackUri !== uri) {
        await this.stop();
      }

      // Если тот же трек, просто продолжим воспроизведение
      if (this.currentTrackUri === uri && this.soundObject) {
        if (!this.isPlaying) {
          await this.soundObject.playAsync();
          this.isPlaying = true;

          // Обновляем уведомление
          await updatePlaybackNotification(
            this.currentTrackName, 
            this.currentArtist, 
            this.isPlaying,
            () => {
              if (this.isPlaying) {
                this.pause();
              } else {
                this.play();
              }
            },
            global.handleNextTrack,
            global.handlePreviousTrack
          );
        }
        return;
      }

      // Загружаем новый трек
      if (!this.soundObject) {
        this.soundObject = new Audio.Sound();
      }

      // Устанавливаем обработчик статуса воспроизведения
      this.soundObject.setOnPlaybackStatusUpdate(this.handlePlaybackStatusUpdate);

      // Загружаем и начинаем воспроизведение
      await this.soundObject.loadAsync({ uri }, { shouldPlay: true });
      this.currentTrackUri = uri;
      this.currentTrackName = trackName;
      this.currentArtist = artist;
      this.isPlaying = true;

      // Создаем уведомление с элементами управления
      await createPlaybackNotification(
        trackName,
        artist,
        this.isPlaying,
        () => {
          if (this.isPlaying) {
            this.pause();
          } else {
            this.play();
          }
        },
        global.handleNextTrack,
        global.handlePreviousTrack
      );
    } catch (error) {
      console.error('Ошибка при загрузке и воспроизведении аудио:', error);
      throw error;
    }
  }

  async pause() {
    if (this.soundObject && this.isPlaying) {
      await this.soundObject.pauseAsync();
      this.isPlaying = false;

      // Обновляем уведомление
      await updatePlaybackNotification(
        this.currentTrackName, 
        this.currentArtist, 
        this.isPlaying,
        () => {
          if (this.isPlaying) {
            this.play();
          } else {
            this.pause();
          }
        },
        global.handleNextTrack,
        global.handlePreviousTrack
      );
    }
  }

  async stop() {
    if (this.soundObject) {
      await this.soundObject.stopAsync();
      await this.soundObject.unloadAsync();
      this.soundObject = null;
      this.currentTrackUri = null;
      this.currentTrackName = '';
      this.isPlaying = false;

      // Удаляем уведомление
      await dismissActiveNotification();
    }
  }

  async play() {
    if (this.soundObject && !this.isPlaying) {
      await this.soundObject.playAsync();
      this.isPlaying = true;

      // Обновляем уведомление
      await updatePlaybackNotification(
        this.currentTrackName, 
        this.currentArtist, 
        this.isPlaying,
        () => {
          if (this.isPlaying) {
            this.pause();
          } else {
            this.play();
          }
        },
        global.handleNextTrack,
        global.handlePreviousTrack
      );
    }
  }

  private handlePlaybackStatusUpdate = async (status: any) => {
    if (status.isLoaded) {
      if (status.didJustFinish) {
        // Трек закончился, можно выполнить действия (например, следующий трек)
        this.isPlaying = false;
        this.currentTrackUri = null;

        // Удаляем уведомление при завершении трека
        await dismissActiveNotification();
      } else if (status.isPlaying) {
        this.isPlaying = true;
      } else {
        this.isPlaying = false;
      }

      // Обновляем уведомление при изменении состояния
      if (this.currentTrackName) {
        await updatePlaybackNotification(
          this.currentTrackName, 
          this.currentArtist, 
          this.isPlaying,
          () => {
            if (this.isPlaying) {
              this.pause();
            } else {
              this.play();
            }
          },
          global.handleNextTrack,
          global.handlePreviousTrack
        );
      }
    }
  };

  getCurrentTrackUri(): string | null {
    return this.currentTrackUri;
  }

  getCurrentTrackName(): string {
    return this.currentTrackName;
  }

  getCurrentArtist(): string {
    return this.currentArtist;
  }

  getIsPlaying(): boolean {
    return this.isPlaying;
  }
}

// Создаем экземпляр сервиса
export const audioPlayerService = new AudioPlayerService();

// Функция для получения метаданных аудио файла
export const getAudioMetadata = async (uri: string) => {
  try {
    const info = await Audio.getAvailableAudioMixturesAsync();
    // В реальной реализации здесь можно получить метаданные трека
    // такие как длительность, название, исполнитель и т.д.
    return info;
  } catch (error) {
    console.error('Ошибка при получении метаданных аудио:', error);
    return null;
  }
};