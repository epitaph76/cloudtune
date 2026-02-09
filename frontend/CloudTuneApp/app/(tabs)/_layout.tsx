// app/(tabs)/_layout.tsx
import { Tabs } from 'expo-router';
import { Ionicons } from '@expo/vector-icons';

export default function TabLayout() {
  return (
    <Tabs
      screenOptions={({ route }) => ({
        tabBarIcon: ({ focused, color, size }) => {
          let iconName = '';

          if (route.name === 'local') {
            iconName = focused ? 'albums' : 'albums-outline';
          } else if (route.name === 'profile') {
            iconName = focused ? 'person' : 'person-outline';
          } else if (route.name === 'cloud') {
            iconName = focused ? 'cloud' : 'cloud-outline';
          }

          return <Ionicons name={iconName as any} size={size} color={color} />;
        },
        tabBarActiveTintColor: '#4CAF50',
        tabBarInactiveTintColor: 'gray',
      })}
    >
      <Tabs.Screen
        name="local"
        options={{
          headerShown: false,
          title: 'Local'
        }}
      />
      <Tabs.Screen
        name="profile"
        options={{
          headerShown: false,
          title: 'Account'
        }}
      />
      <Tabs.Screen
        name="cloud"
        options={{
          headerShown: false,
          title: 'Cloud'
        }}
      />
    </Tabs>
  );
}