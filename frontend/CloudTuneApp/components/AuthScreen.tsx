// components/AuthScreen.tsx
import React, { useState } from 'react';
import { View, Text, StyleSheet, Alert, ScrollView } from 'react-native';
import { useRouter } from 'expo-router';
import { registerUser, loginUser } from '@/lib/api';
import { storeToken } from '@/lib/authStorage';
import CustomInput from '@/components/CustomInput';
import CustomButton from '@/components/CustomButton';
import { useAuthMode } from '@/contexts/AuthModeContext';

type AuthMode = 'login' | 'register';

interface FormData {
  email: string;
  username?: string;
  password: string;
}

const AuthScreen = () => {
  const router = useRouter();
  const { setIsAuthenticated, setUserData } = useAuth();
  const { authMode, setAuthMode } = useAuthMode();
  const [formData, setFormData] = useState<FormData>({
    email: '',
    username: '',
    password: '',
  });
  const [loading, setLoading] = useState(false);

  const handleInputChange = (field: keyof FormData, value: string) => {
    setFormData(prev => ({
      ...prev,
      [field]: value
    }));
  };

  const handleSubmit = async () => {
    if (!formData.email || !formData.password) {
      Alert.alert('Ошибка', 'Пожалуйста, заполните все обязательные поля');
      return;
    }

    if (authMode === 'register' && !formData.username) {
      Alert.alert('Ошибка', 'Пожалуйста, укажите имя пользователя');
      return;
    }

    setLoading(true);

    try {
      let response;

      if (authMode === 'register') {
        response = await registerUser({
          email: formData.email,
          username: formData.username!,
          password: formData.password,
        });
      } else {
        response = await loginUser({
          email: formData.email,
          password: formData.password,
        });
      }

      // Сохраняем токен после успешной регистрации или входа
      if (response.token) {
        await storeToken(response.token);
        
        // Обновляем состояние аутентификации
        setIsAuthenticated(true);
        
        // Обновляем данные пользователя
        setUserData(response.user || {
          id: 'mock-id',
          email: formData.email,
          username: formData.username || 'New User'
        });
        
        // Перенаправляем пользователя на главный экран
        router.replace('/(tabs)');
      }
    } catch (error: any) {
      console.error('Ошибка аутентификации:', error);
      Alert.alert('Ошибка', error.message || 'Произошла ошибка при аутентификации');
    } finally {
      setLoading(false);
    }
  };

  return (
    <ScrollView contentContainerStyle={styles.container}>
      <View style={styles.logoContainer}>
        <Text style={styles.logo}>🎵</Text>
        <Text style={styles.appName}>CloudTune</Text>
      </View>

      <View style={styles.formContainer}>
        <Text style={styles.title}>
          {authMode === 'login' ? 'Добро пожаловать!' : 'Создать аккаунт'}
        </Text>
        <Text style={styles.subtitle}>
          {authMode === 'login' 
            ? 'Войдите в свой аккаунт, чтобы продолжить' 
            : 'Зарегистрируйтесь, чтобы начать слушать музыку'}
        </Text>

        <View style={styles.form}>
          <CustomInput
            label="Email"
            placeholder="Введите ваш email"
            value={formData.email}
            onChangeText={(value) => handleInputChange('email', value)}
            keyboardType="email-address"
            autoCapitalize="none"
          />

          {authMode === 'register' && (
            <CustomInput
              label="Имя пользователя"
              placeholder="Введите имя пользователя"
              value={formData.username || ''}
              onChangeText={(value) => handleInputChange('username', value)}
              autoCapitalize="none"
            />
          )}

          <CustomInput
            label="Пароль"
            placeholder="Введите пароль"
            value={formData.password}
            onChangeText={(value) => handleInputChange('password', value)}
            secureTextEntry={true}
          />

          <CustomButton
            title={loading ? 'Загрузка...' : (authMode === 'login' ? 'Войти' : 'Зарегистрироваться')}
            onPress={handleSubmit}
            disabled={loading}
            style={styles.submitButton}
          />

          <View style={styles.divider}>
            <View style={styles.line} />
            <Text style={styles.orText}>или</Text>
            <View style={styles.line} />
          </View>

          <CustomButton
            title={authMode === 'login' 
              ? 'Нет аккаунта? Зарегистрироваться' 
              : 'Уже есть аккаунт? Войти'}
            onPress={() => {
              const newMode = authMode === 'login' ? 'register' : 'login';
              setAuthMode(newMode);
              // Обновляем URL, чтобы сохранить состояние при перезагрузке
              router.setParams({ mode: newMode });
            }}
            style={styles.toggleButton}
            titleStyle={styles.toggleButtonText}
          />
        </View>
      </View>
    </ScrollView>
  );
};

const styles = StyleSheet.create({
  container: {
    flexGrow: 1,
    justifyContent: 'center',
    padding: 20,
    backgroundColor: '#f0f8ff',
  },
  logoContainer: {
    alignItems: 'center',
    marginBottom: 40,
  },
  logo: {
    fontSize: 60,
    marginBottom: 10,
  },
  appName: {
    fontSize: 28,
    fontWeight: 'bold',
    color: '#4CAF50',
  },
  formContainer: {
    width: '100%',
  },
  title: {
    fontSize: 28,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 8,
    color: '#333',
  },
  subtitle: {
    fontSize: 16,
    textAlign: 'center',
    marginBottom: 30,
    color: '#666',
  },
  form: {
    backgroundColor: 'white',
    padding: 25,
    borderRadius: 15,
    shadowColor: '#000',
    shadowOffset: {
      width: 0,
      height: 4,
    },
    shadowOpacity: 0.1,
    shadowRadius: 6,
    elevation: 5,
  },
  submitButton: {
    marginTop: 10,
  },
  divider: {
    flexDirection: 'row',
    alignItems: 'center',
    marginVertical: 20,
  },
  line: {
    flex: 1,
    height: 1,
    backgroundColor: '#ddd',
  },
  orText: {
    marginHorizontal: 10,
    color: '#888',
  },
  toggleButton: {
    backgroundColor: 'transparent',
    padding: 10,
  },
  toggleButtonText: {
    color: '#2196F3',
    fontSize: 15,
  },
});

export default AuthScreen;