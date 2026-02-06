// storage/authStorage.ts
import AsyncStorage from '@react-native-async-storage/async-storage';

const TOKEN_KEY = 'cloudtune_token';

export const storeToken = async (token: string) => {
  try {
    await AsyncStorage.setItem(TOKEN_KEY, token);
  } catch (error) {
    console.error('Ошибка при сохранении токена:', error);
  }
};

export const getToken = async () => {
  try {
    const token = await AsyncStorage.getItem(TOKEN_KEY);
    return token;
  } catch (error) {
    console.error('Ошибка при получении токена:', error);
    return null;
  }
};

export const removeToken = async () => {
  try {
    await AsyncStorage.removeItem(TOKEN_KEY);
  } catch (error) {
    console.error('Ошибка при удалении токена:', error);
  }
};