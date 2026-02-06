// providers/AuthProvider.tsx
import React, { createContext, useContext, useEffect, useState, ReactNode } from 'react';
import { getToken } from '@/lib/authStorage';

interface AuthContextType {
  isAuthenticated: boolean;
  loading: boolean;
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
  const [loading, setLoading] = useState(true);

  useEffect(() => {
    checkAuthStatus();
  }, []);

  const checkAuthStatus = async () => {
    try {
      const token = await getToken();
      setIsAuthenticated(!!token);
    } catch (error) {
      console.error('Ошибка при проверке статуса аутентификации:', error);
      setIsAuthenticated(false);
    } finally {
      setLoading(false);
    }
  };

  return (
    <AuthContext.Provider value={{ isAuthenticated, loading }}>
      {children}
    </AuthContext.Provider>
  );
}