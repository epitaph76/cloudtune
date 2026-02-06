// components/ProfileScreen.tsx
import React, { useState } from 'react';
import { View, Text, TouchableOpacity, StyleSheet, Alert } from 'react-native';
import { useRouter } from 'expo-router';
import { useAuth } from '@/providers/AuthProvider';

const ProfileScreen = () => {
  const router = useRouter();
  const { logout, userData } = useAuth();

  const handleLogin = () => {
    // Перенаправляем на страницу аутентификации в режиме входа
    router.push('/?mode=login');
  };

  const handleRegister = () => {
    // Перенаправляем на страницу аутентификации в режиме регистрации
    router.push('/?mode=register');
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
          <Text style={styles.label}>ID:</Text>
          <Text style={styles.value}>{userData.id}</Text>
          
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

  // Если нет данных профиля, показываем кнопки входа и регистрации
  return (
    <View style={styles.container}>
      <Text style={styles.title}>CloudTune</Text>
      <Text style={styles.subtitle}>Профиль пользователя</Text>
      
      <View style={styles.buttonContainer}>
        <TouchableOpacity style={styles.button} onPress={handleLogin}>
          <Text style={styles.buttonText}>Войти</Text>
        </TouchableOpacity>
        
        <TouchableOpacity style={styles.button} onPress={handleRegister}>
          <Text style={styles.buttonText}>Зарегистрироваться</Text>
        </TouchableOpacity>
      </View>
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
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 10,
    color: '#333',
  },
  subtitle: {
    fontSize: 18,
    textAlign: 'center',
    marginBottom: 40,
    color: '#666',
  },
  buttonContainer: {
    flexDirection: 'column',
    gap: 15,
  },
  button: {
    backgroundColor: '#4CAF50',
    padding: 16,
    borderRadius: 10,
    alignItems: 'center',
    shadowColor: '#4CAF50',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 3,
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
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