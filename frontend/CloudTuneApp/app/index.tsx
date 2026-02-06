// app/index.tsx
import React, { useState } from 'react';
import { View, Text, TextInput, Button, StyleSheet, Alert } from 'react-native';
import { registerUser } from '@/lib/api';

export default function Index() {
  const [email, setEmail] = useState('');
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');

  const handleRegister = async () => {
    try {
      const response = await registerUser({
        email,
        username,
        password
      });
      Alert.alert('Успех', `Регистрация прошла успешно! ${response.message}`);
      console.log('Регистрация успешна:', response);
    } catch (error: any) {
      Alert.alert('Ошибка', error.message || 'Ошибка при регистрации');
      console.error('Ошибка регистрации:', error);
    }
  };

  return (
    <View style={styles.container}>
      <Text style={styles.title}>Регистрация в CloudTune</Text>
      
      <TextInput
        style={styles.input}
        placeholder="Email"
        value={email}
        onChangeText={setEmail}
        keyboardType="email-address"
        autoCapitalize="none"
      />
      
      <TextInput
        style={styles.input}
        placeholder="Имя пользователя"
        value={username}
        onChangeText={setUsername}
        autoCapitalize="none"
      />
      
      <TextInput
        style={styles.input}
        placeholder="Пароль"
        value={password}
        onChangeText={setPassword}
        secureTextEntry
      />
      
      <Button title="Зарегистрироваться" onPress={handleRegister} />
    </View>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    padding: 20,
  },
  title: {
    fontSize: 24,
    fontWeight: 'bold',
    textAlign: 'center',
    marginBottom: 20,
  },
  input: {
    borderWidth: 1,
    borderColor: '#ddd',
    padding: 10,
    marginBottom: 10,
    borderRadius: 5,
  },
});