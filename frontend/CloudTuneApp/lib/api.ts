import AsyncStorage from '@react-native-async-storage/async-storage';

// Используем домен сервера вместо локального адреса
const BASE_URL = 'http://192.168.31.128:8080'; // URL вашего бэкенда

// Получение токена из хранилища
const getToken = async () => {
  try {
    const token = await AsyncStorage.getItem('cloudtune_token'); // Используем правильный ключ
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

    const result = await response.json();
    
    // Проверяем, что в ответе есть нужные данные
    if (!result.token || !result.user) {
      throw new Error('Неверный формат ответа от сервера');
    }
    
    return result;
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

    const result = await response.json();
    
    // Проверяем, что в ответе есть нужные данные
    if (!result.token || !result.user) {
      throw new Error('Неверный формат ответа от сервера');
    }
    
    return result;
  } catch (error) {
    console.error('Ошибка при входе пользователя:', error);
    throw error;
  }
};

// Получение профиля пользователя (защищенный маршрут)
export const getUserProfile = async () => {
  try {
    const response = await fetch(`${BASE_URL}/api/profile`, {
      method: 'GET',
      headers: await getHeaders(true), // Включаем аутентификацию
    });

    if (!response.ok) {
      const errorData = await response.json();
      throw new Error(errorData.error || 'Ошибка при получении профиля');
    }

    const result = await response.json();
    
    // Проверяем, что в ответе есть нужные данные
    if (!result.user) {
      throw new Error('Неверный формат ответа от сервера');
    }
    
    return result;
  } catch (error: any) {
    console.error('Ошибка при получении профиля пользователя:', error);
    throw error;
  }
};