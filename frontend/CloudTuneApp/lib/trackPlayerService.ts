import TrackPlayer, { Event, RepeatMode, State } from 'react-native-track-player';

// Инициализация аудио сервиса
export const initializeAudioService = async () => {
  try {
    // Инициализация TrackPlayer
    await TrackPlayer.setupPlayer();

    // Добавление слушателей событий
    TrackPlayer.addEventListener(Event.PlaybackTrackChanged, async (data) => {
      console.log('Трек изменился:', data);
    });

    TrackPlayer.addEventListener(Event.PlaybackState, async (data) => {
      console.log('Состояние воспроизведения изменилось:', data);
    });

    TrackPlayer.addEventListener(Event.PlaybackError, (data) => {
      console.warn('Ошибка воспроизведения:', data);
    });

    console.log('Аудио сервис инициализирован');
  } catch (error) {
    console.error('Ошибка при инициализации аудио сервиса:', error);
  }
};

// Класс для управления воспроизведением аудио
class AudioPlayerService {
  private isInitialized = false;

  constructor() {
    this.initialize();
  }

  private async initialize() {
    if (!this.isInitialized) {
      await initializeAudioService();
      this.isInitialized = true;
    }
  }

  // Добавление трека в очередь
  async addTrack(track: {
    id: string;
    url: string;
    title: string;
    artist: string;
    artwork?: string;
  }) {
    await TrackPlayer.add({
      id: track.id,
      url: track.url,
      title: track.title,
      artist: track.artist,
      artwork: track.artwork,
    });
  }

  // Воспроизведение трека по ID
  async playTrack(trackId: string) {
    // Очищаем очередь
    await TrackPlayer.reset();
    
    // Добавляем трек в очередь
    const tracks = await TrackPlayer.getQueue();
    const trackIndex = tracks.findIndex(track => track.id === trackId);
    
    if (trackIndex !== -1) {
      await TrackPlayer.skip(trackIndex);
      await TrackPlayer.play();
    }
  }

  // Воспроизведение
  async play() {
    await TrackPlayer.play();
  }

  // Пауза
  async pause() {
    await TrackPlayer.pause();
  }

  // Остановка
  async stop() {
    await TrackPlayer.stop();
  }

  // Следующий трек
  async skipToNext() {
    try {
      await TrackPlayer.skipToNext();
    } catch (error) {
      console.log('Нет следующего трека');
    }
  }

  // Предыдущий трек
  async skipToPrevious() {
    try {
      await TrackPlayer.skipToPrevious();
    } catch (error) {
      console.log('Нет предыдущего трека');
    }
  }

  // Установка громкости
  async setVolume(volume: number) {
    await TrackPlayer.setVolume(volume);
  }

  // Получение текущего состояния воспроизведения
  async getPlaybackState() {
    return await TrackPlayer.getPlaybackState();
  }

  // Получение текущего трека
  async getCurrentTrack() {
    const trackIndex = await TrackPlayer.getCurrentTrack();
    if (trackIndex !== null) {
      const queue = await TrackPlayer.getQueue();
      return queue[trackIndex];
    }
    return null;
  }

  // Получение позиции воспроизведения
  async getPosition() {
    return await TrackPlayer.getPosition();
  }

  // Получение длительности трека
  async getDuration() {
    return await TrackPlayer.getDuration();
  }

  // Перемотка к позиции
  async seekTo(position: number) {
    await TrackPlayer.seekTo(position);
  }

  // Очистка очереди
  async clearQueue() {
    await TrackPlayer.reset();
  }

  // Управление повтором
  async setRepeatMode(mode: RepeatMode) {
    await TrackPlayer.setRepeatMode(mode);
  }
}

// Создаем экземпляр сервиса
export const audioPlayerService = new AudioPlayerService();

// Функция для получения метаданных аудио файла
export const getAudioMetadata = async (uri: string) => {
  // В реальной реализации здесь можно получить метаданные трека
  // такие как длительность, название, исполнитель и т.д.
  return {
    uri,
    duration: await TrackPlayer.getDuration(),
  };
};