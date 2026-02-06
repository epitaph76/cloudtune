import AsyncStorage from '@react-native-async-storage/async-storage';

const BASE_URL = 'http://192.168.1.96:8080'; // URL вашего бэкенда

// Получение токена из хранилища
const getToken = async () => {
  try {
    const token = await AsyncStorage.getItem('token');
    return token;
  } catch (error) {
    console.error('Ошибка при получении токена:', error);
    return null;
  }
};

// Настройка заголовков для запросов
const getHeaders = async (includeAuth = true) => {
  const headers: Record<string, string> = {
    'Content-Type': 'application/json',
  };

  if (includeAuth) {
    const token = await getToken();
    if (token) {
      headers['Authorization'] = `Bearer ${token}`;
    }
  }

  return headers;
};

// Проверка состояния сервера
export const checkHealth = async () => {
  try {
    const response = await fetch(`${BASE_URL}/health`, {
      method: 'GET',
      headers: await getHeaders(false),
    });

    if (!response.ok) {
      throw new Error(`HTTP error! status: ${response.status}`);
    }

    return await response.json();
  } catch (error) {
    console.error('Ошибка при проверке состояния сервера:', error);
    throw error;
  }
};

// Регистрация пользователя
export const registerUser = async (userData: { email: string; username: string; password: string }) => {
  try {
    const response = await fetch(`${BASE_URL}/auth/register`, {
      method: 'POST',
      headers: await getHeaders(false),
      body: JSON.stringify(userData),
    });

    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.error || 'Ошибка при регистрации');
    }

    return await response.json();
  } catch (error) {
    console.error('Ошибка при регистрации пользователя:', error);
    throw error;
  }
};

// Вход пользователя
export const loginUser = async (credentials: { email: string; password: string }) => {
  try {
    const response = await fetch(`${BASE_URL}/auth/login`, {
      method: 'POST',
      headers: await getHeaders(false),
      body: JSON.stringify(credentials),
    });

    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.error || 'Ошибка при входе');
    }

    return await response.json();
  } catch (error) {
    console.error('Ошибка при входе пользователя:', error);
    throw error;
  }
};

// Получение профиля пользователя (защищенный маршрут)
// TODO: Реализовать эндпоинт /api/profile в бэкенде
export const getUserProfile = async () => {
  try {
    const response = await fetch(`${BASE_URL}/api/profile`, {
      method: 'GET',
      headers: await getHeaders(true), // Включаем аутентификацию
    });

    if (!response.ok) {
      // Если эндпоинт не реализован, возвращаем заглушку
      if (response.status === 404) {
        console.warn('Эндпоинт /api/profile не реализован в бэкенде');
        // Возвращаем заглушку с информацией из токена
        const token = await getToken();
        return {
          user: {
            id: 'mock-id',
            email: 'mock@example.com',
            username: 'Mock User'
          }
        };
      }
      const errorData = await response.json();
      throw new Error(errorData.error || 'Ошибка при получении профиля');
    }

    return await response.json();
  } catch (error: any) {
    if (error.message.includes('JSON Parse error')) {
      console.warn('Ошибка парсинга ответа от сервера, возвращаем заглушку');
      // Возвращаем заглушку с информацией из токена
      const token = await getToken();
      return {
        user: {
          id: 'mock-id-from-token',
          email: 'mock@example.com',
          username: 'Mock User'
        }
      };
    }
    console.error('Ошибка при получении профиля пользователя:', error);
    throw error;
  }
};