// providers/AuthProvider.tsx
import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { getToken, removeToken } from '@/lib/authStorage';

interface UserData {
  id: string;
  email: string;
  username: string;
}

interface AuthContextType {
  isAuthenticated: boolean;
  loading: boolean;
  userData: UserData | null;
  login: (userData: UserData, token: string) => Promise<void>;
  logout: () => Promise<void>;
}

const AuthContext = createContext<AuthContextType | undefined>(undefined);

export const useAuth = () => {
  const context = useContext(AuthContext);
  if (context === undefined) {
    throw new Error('useAuth must be used within an AuthProvider');
  }
  return context;
};

interface AuthProviderProps {
  children: ReactNode;
}

export default function AuthProvider({ children }: AuthProviderProps) {
  const [isAuthenticated, setIsAuthenticated] = useState(false);
  const [userData, setUserData] = useState<UserData | null>(null);
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    checkAuthStatus();
  }, []);

  const checkAuthStatus = async () => {
    try {
      const token = await getToken();
      if (token) {
        // В реальном приложении здесь мы бы декодировали токен или сделали запрос к API
        // для получения данных пользователя, но пока что просто установим isAuthenticated
        setIsAuthenticated(true);
      }
    } catch (error) {
      console.error('Ошибка при проверке статуса аутентификации:', error);
      setIsAuthenticated(false);
      setUserData(null);
    } finally {
      setLoading(false);
    }
  };

  const login = async (userData: UserData, token: string) => {
    try {
      // Сохраняем токен
      await import('@/lib/authStorage').then(async (module) => {
        await module.storeToken(token);
      });
      
      // Устанавливаем данные пользователя
      setUserData(userData);
      setIsAuthenticated(true);
    } catch (error) {
      console.error('Ошибка при входе:', error);
    }
  };

  const logout = async () => {
    try {
      // Удаляем токен
      await removeToken();
      
      // Сбрасываем состояние
      setUserData(null);
      setIsAuthenticated(false);
    } catch (error) {
      console.error('Ошибка при выходе:', error);
    }
  };

  return (
    <AuthContext.Provider value={{ 
      isAuthenticated, 
      loading, 
      userData, 
      login, 
      logout 
    }}>
      {children}
    </AuthContext.Provider>
  );
}