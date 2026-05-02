import { Stack } from "expo-router/stack";

export default function RootLayout() {
  return (
    <Stack>
      <Stack.Screen
        name="index"
        options={{
          title: "FastRead",
          headerLargeTitle: true,
          headerTransparent: false,
        }}
      />
    </Stack>
  );
}
