import { Audio, AVPlaybackStatus } from 'expo-av';
import * as MediaLibrary from 'expo-media-library';
import * as Notifications from 'expo-notifications';
import { Platform } from 'react-native';

// Инициализация уведомлений
Notifications.setNotificationHandler({
  handleNotification: async () => ({
    shouldShowAlert: false,
    shouldPlaySound: false,
    shouldSetBadge: false,
  }),
});

// Создание канала уведомлений для Android
export const createPlaybackChannel = async () => {
  if (Platform.OS === 'android') {
    await Notifications.setNotificationChannelAsync('music-playback-channel', {
      name: 'Music Playback',
      importance: Notifications.AndroidImportance.LOW, // Низкий уровень важности
      vibrationPattern: [], // Без вибрации
      sound: null, // Без звука
      showBadge: false, // Не показывать бейдж
    });
  }
};

// Глобальный объект для хранения ID уведомления
let activeNotificationId: string | null = null;

// Создание уведомления с элементами управления воспроизведением
export const createPlaybackNotification = async (
  title: string,
  artist: string,
  isPlaying: boolean,
  onTogglePlayback: () => void,
  onNext?: () => void,
  onPrevious?: () => void
) => {
  try {
    // Запрос разрешений на отправку уведомлений
    const { status } = await Notifications.requestPermissionsAsync();
    if (status !== 'granted') {
      console.log('Разрешение на уведомления не получено');
      return null;
    }

    // Определяем значок воспроизведения
    const playbackIcon = isPlaying ? 'pause' : 'play';

    // Создаем уведомление с элементами управления
    const notificationId = await Notifications.scheduleNotificationAsync({
      content: {
        title: title,
        body: artist,
        sound: null, // Отключаем звук уведомления
        priority: Notifications.AndroidNotificationPriority.LOW, // Низкий приоритет
        data: {
          type: 'playback_control',
        },
        // Добавляем действия воспроизведения
        ...(Platform.OS === 'android' && {
          android: {
            channelId: 'music-playback-channel',
            color: '#4CAF50',
            groupSummary: false,
            sticky: true, // Уведомление остается до отмены
            actions: [
              ...(onPrevious ? [{ 
                identifier: 'PREVIOUS', 
                title: 'Previous'
              }] : []),
              {
                identifier: 'TOGGLE_PLAYBACK',
                title: isPlaying ? 'Pause' : 'Play',
                requiresAuthentication: false,
                destructive: false,
                foreground: true
              },
              ...(onNext ? [{ 
                identifier: 'NEXT', 
                title: 'Next'
              }] : []),
            ],
          },
        }),
      },
      trigger: null, // Постоянное уведомление
    });

    // Сохраняем ID активного уведомления
    activeNotificationId = notificationId;

    return notificationId;
  } catch (error) {
    console.error('Ошибка при создании уведомления воспроизведения:', error);
    return null;
  }
};

// Обновление уведомления - для Android это требует пересоздания
export const updatePlaybackNotification = async (
  title: string,
  artist: string,
  isPlaying: boolean,
  onTogglePlayback: () => void,
  onNext?: () => void,
  onPrevious?: () => void
) => {
  if (!activeNotificationId) {
    console.log('Нет активного уведомления для обновления, создаем новое');
    // Если нет активного уведомления, создаем его
    await createPlaybackNotification(title, artist, isPlaying, onTogglePlayback, onNext, onPrevious);
    return;
  }

  try {
    // Отменяем старое уведомление
    await Notifications.dismissNotificationAsync(activeNotificationId);

    // Создаем новое с обновленным состоянием
    const newNotificationId = await createPlaybackNotification(
      title, 
      artist, 
      isPlaying, 
      onTogglePlayback, 
      onNext, 
      onPrevious
    );

    // Обновляем ID активного уведомления
    if (newNotificationId) {
      activeNotificationId = newNotificationId;
    }
    
    console.log('Уведомление обновлено: ', { title, artist, isPlaying });
  } catch (error) {
    console.error('Ошибка при обновлении уведомления:', error);
  }
};

// Отмена активного уведомления
export const dismissActiveNotification = async () => {
  if (activeNotificationId) {
    try {
      await Notifications.dismissNotificationAsync(activeNotificationId);
      activeNotificationId = null;
    } catch (error) {
      console.error('Ошибка при отмене активного уведомления:', error);
    }
  }
};

// Инициализация сервиса уведомлений
export const initializeNotificationService = async () => {
  try {
    // Создаем канал уведомлений
    await createPlaybackChannel();

    // Обработка действий уведомления
    if (Platform.OS === 'android') {
      Notifications.addNotificationResponseReceivedListener(response => {
        const actionIdentifier = response.actionIdentifier;

        switch(actionIdentifier) {
          case 'TOGGLE_PLAYBACK':
            // Вызов глобального обработчика переключения воспроизведения
            global.handleTogglePlayback?.();
            break;
          case 'NEXT':
            global.handleNextTrack?.();
            break;
          case 'PREVIOUS':
            global.handlePreviousTrack?.();
            break;
        }
      });
    }
  } catch (error) {
    console.error('Ошибка при инициализации сервиса уведомлений:', error);
  }
};

// Получение ID активного уведомления
export const getActiveNotificationId = (): string | null => {
  return activeNotificationId;
};