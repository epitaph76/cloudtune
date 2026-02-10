import React from 'react';
import { View, Text, TouchableOpacity, StyleSheet } from 'react-native';
import { useRouter } from 'expo-router';
import { ThemedView } from '@/components/themed-view';
import { ThemedText } from '@/components/themed-text';

export default function CloudStorageScreen() {
  const router = useRouter();

  const goToCloud = () => {
    // Переход на заглушку облачного хранилища
    router.push('/(tabs)/cloud');
  };

  const goToLocalStorage = () => {
    // Переход на страницу локального хранилища
    router.push('/(tabs)/local');
  };

  return (
    <ThemedView style={styles.container}>
      <ThemedText type="title">Cloud Storage</ThemedText>
      <Text style={styles.descriptionText}>Выберите тип хранилища</Text>
      
      <View style={styles.buttonContainer}>
        <TouchableOpacity 
          style={styles.storageButton}
          onPress={goToCloud}
        >
          <ThemedText type="buttonText" style={styles.buttonText}>
            Облако
          </ThemedText>
        </TouchableOpacity>
        
        <TouchableOpacity 
          style={styles.storageButton}
          onPress={goToLocalStorage}
        >
          <ThemedText type="buttonText" style={styles.buttonText}>
            Локальное хранилище
          </ThemedText>
        </TouchableOpacity>
      </View>
    </ThemedView>
  );
}

const styles = StyleSheet.create({
  container: {
    flex: 1,
    justifyContent: 'center',
    alignItems: 'center',
    padding: 20,
  },
  descriptionText: {
    fontSize: 16,
    marginTop: 10,
    color: '#888',
    textAlign: 'center',
    marginBottom: 40,
  },
  buttonContainer: {
    width: '100%',
    gap: 20,
  },
  storageButton: {
    backgroundColor: '#2196F3',
    paddingVertical: 20,
    paddingHorizontal: 20,
    borderRadius: 10,
    alignItems: 'center',
    marginVertical: 10,
    shadowColor: '#2196F3',
    shadowOffset: {
      width: 0,
      height: 2,
    },
    shadowOpacity: 0.3,
    shadowRadius: 4,
    elevation: 3,
  },
  buttonText: {
    fontSize: 18,
    fontWeight: 'bold',
    color: 'white',
  },
});
