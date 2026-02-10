// components/ProfileScreen.tsx
import React, { useState } from 'react';
import { View, Text, TextInput, TouchableOpacity, StyleSheet, Alert, ActivityIndicator } from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/providers/AuthProvider';
import { registerUser, loginUser } from '@/lib/api';

const ProfileScreen = () => {
  const router = useRouter();
  const { login, logout, userData } = useAuth();
  
  // Состояния для формы аутентификации
  const [email, setEmail] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [loading, setLoading] = useState(false);
  const [isLoginMode, setIsLoginMode] = useState(true); // true для входа, false для регистрации

  const handleAuth = async () => {
    if (!email || !password) {
      Alert.alert('Ошибка', 'Пожалуйста, заполните email и пароль');
      return;
    }

    if (!isLoginMode && !username) {
      Alert.alert('Ошибка', 'Пожалуйста, заполните имя пользователя');
      return;
    }

    if (!isLoginMode && password.length < 6) {
      Alert.alert('Ошибка', 'Пароль должен быть не менее 6 символов');
      return;
    }

    setLoading(true);
    try {
      let response;
      if (isLoginMode) {
        // Вход
        response = await loginUser({
          email,
          password
        });
      } else {
        // Регистрация
        response = await registerUser({
          email,
          username,
          password
        });
      }

      // Вызываем функцию login из AuthProvider
      if (response.token && response.user) {
        await login(response.user, response.token);
      }

      Alert.alert('Успех', isLoginMode ? 'Вы успешно вошли!' : 'Вы успешно зарегистрировались!');
      
      // Очищаем поля
      setEmail('');
      setUsername('');
      setPassword('');
    } catch (error: any) {
      Alert.alert('Ошибка', error.message || (isLoginMode ? 'Ошибка при входе' : 'Ошибка при регистрации'));
      console.error(isLoginMode ? 'Ошибка входа:' : 'Ошибка регистрации:', error);
    } finally {
      setLoading(false);
    }
  };

  const handleLogout = async () => {
    await logout();
  };

  // Если есть данные профиля, отображаем их
  if (userData) {
    return (
      <View style={styles.container}>
        <Text style={styles.title}>Профиль пользователя</Text>

        <View style={styles.profileInfo}>
          <Text style={styles.label}>Email:</Text>
          <Text style={styles.value}>{userData.email}</Text>

          <Text style={styles.label}>Имя пользователя:</Text>
          <Text style={styles.value}>{userData.username}</Text>
        </View>

        <TouchableOpacity style={styles.logoutButton} onPress={handleLogout}>
          <Text style={styles.logoutButtonText}>Выйти</Text>
        </TouchableOpacity>
      </View>
    );
  }

  // Если нет данных профиля, показываем форму аутентификации
  return (
    <View style={styles.container}>
      <Text style={styles.title}>{isLoginMode ? 'Вход в CloudTune' : 'Регистрация в CloudTune'}</Text>

      <TextInput
        style={styles.input}
        placeholder="Email"
        value={email}
        onChangeText={setEmail}
        keyboardType="email-address"
        autoCapitalize="none"
        autoComplete="email"
      />

      {!isLoginMode && (
        <TextInput
          style={styles.input}
          placeholder="Имя пользователя"
          value={username}
          onChangeText={setUsername}
          autoCapitalize="none"
          autoComplete="username"
        />
      )}

      <TextInput
        style={styles.input}
        placeholder="Пароль"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
        autoComplete="password"
      />

      {loading ? (
        <ActivityIndicator size="large" color="#4CAF50" style={styles.loading} />
      ) : (
        <TouchableOpacity style={styles.authButton} onPress={handleAuth}>
          <Text style={styles.buttonText}>{isLoginMode ? 'Войти' : 'Зарегистрироваться'}</Text>
        </TouchableOpacity>
      )}

      <TouchableOpacity style={styles.toggleModeButton} onPress={() => setIsLoginMode(!isLoginMode)}>
        <Text style={styles.toggleModeButtonText}>
          {isLoginMode 
            ? 'Нет аккаунта? Зарегистрироваться' 
            : 'Уже есть аккаунт? Войти'}
        </Text>
      </TouchableOpacity>
    </View>
  );
};

const styles = StyleSheet.create({
  container: {
    flex: 1,
    padding: 20,
    backgroundColor: '#f5f5f5',
    justifyContent: 'center',
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 30,
    color: '#333',
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    padding: 15,
    marginBottom: 15,
    borderRadius: 8,
    backgroundColor: 'white',
    fontSize: 16,
  },
  authButton: {
    backgroundColor: '#4CAF50',
    padding: 16,
    borderRadius: 10,
    alignItems: 'center',
    marginTop: 10,
    shadowColor: '#4CAF50',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 3,
  },
  toggleModeButton: {
    marginTop: 20,
    alignItems: 'center',
  },
  toggleModeButtonText: {
    color: '#2196F3',
    fontSize: 16,
    fontWeight: 'bold',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
  loading: {
    marginTop: 20,
  },
  profileInfo: {
    backgroundColor: 'white',
    padding: 20,
    borderRadius: 10,
    marginBottom: 20,
  },
  label: {
    fontSize: 16,
    fontWeight: 'bold',
    color: '#666',
    marginTop: 10,
  },
  value: {
    fontSize: 16,
    color: '#333',
    paddingLeft: 10,
  },
  logoutButton: {
    backgroundColor: '#f44336',
    padding: 15,
    borderRadius: 8,
    alignItems: 'center',
  },
  logoutButtonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
});

export default ProfileScreen;