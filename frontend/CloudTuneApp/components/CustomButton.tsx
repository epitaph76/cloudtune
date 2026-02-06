// components/CustomButton.tsx
import React from 'react';
import { TouchableOpacity, Text, StyleSheet } from 'react-native';

interface CustomButtonProps {
  title: string;
  onPress: () => void;
  style?: object;
  titleStyle?: object;
  disabled?: boolean;
}

const CustomButton = ({ 
  title, 
  onPress, 
  style, 
  titleStyle, 
  disabled = false 
}: CustomButtonProps) => {
  return (
    <TouchableOpacity 
      style={[
        styles.button, 
        disabled && styles.disabledButton,
        style
      ]} 
      onPress={onPress}
      disabled={disabled}
    >
      <Text style={[styles.buttonText, titleStyle]}>
        {title}
      </Text>
    </TouchableOpacity>
  );
};

const styles = StyleSheet.create({
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
  disabledButton: {
    backgroundColor: '#A5D6A7',
  },
  buttonText: {
    color: 'white',
    fontSize: 16,
    fontWeight: 'bold',
  },
});

export default CustomButton;