// System-managed layout — extend in place, never rewrite from scratch.
// Keep the provider chain intact: ErrorBoundary → OneDollarStats → SafeArea → QueryClient.
// To switch navigation, replace only the <Slot /> line with <Stack /> or <Tabs />.
import { useEffect } from "react";
import { useFonts } from "expo-font";
import { Cinzel_400Regular, Cinzel_600SemiBold } from "@expo-google-fonts/cinzel";
import { Inter_400Regular, Inter_500Medium, Inter_600SemiBold } from "@expo-google-fonts/inter";
import { View, ActivityIndicator } from "react-native";
import { Slot } from "expo-router";
import { StatusBar } from "expo-status-bar";
import { SafeAreaProvider } from "react-native-safe-area-context";
import { QueryClient, QueryClientProvider } from "@tanstack/react-query";
import { ErrorBoundary } from "../components/__ErrorBoundary";
import { OneDollarStatsProvider } from "../lib/__analytics";
import { isWeb, startWebSafeArea } from "../lib/__web-safe-area";
import appJson from "../app.json";

const queryClient = new QueryClient();

const applicationId = appJson.expo.extra.applicationId ?? "";
const hostname = applicationId ? `${applicationId}-mobile` : "localhost";

export default function RootLayout() {
  const [fontsLoaded, fontError] = useFonts({ Cinzel_400Regular, Cinzel_600SemiBold, Inter_400Regular, Inter_500Medium, Inter_600SemiBold });
  useEffect(() => {
    if (isWeb) startWebSafeArea();
  }, []);

  if (!fontsLoaded && !fontError) return <View style={{ flex: 1, backgroundColor: '#0C0D0E', alignItems: 'center', justifyContent: 'center' }}><ActivityIndicator color="#C3A16A" /></View>;
  return (
    <ErrorBoundary>
      {/* Runable analytics provider — do not remove, required for analytics tracking */}
      <OneDollarStatsProvider
        config={{
          hostname,
          collectorUrl: "https://r.lilstts.com/events",
          devmode: true,
        }}
      >
        <SafeAreaProvider>
          <QueryClientProvider client={queryClient}>
            <StatusBar style="light" />
            <Slot />
          </QueryClientProvider>
        </SafeAreaProvider>
      </OneDollarStatsProvider>
    </ErrorBoundary>
  );
}
