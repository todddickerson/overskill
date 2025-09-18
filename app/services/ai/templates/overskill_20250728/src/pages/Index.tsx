import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card";

export default function Index() {
  const [count, setCount] = useState(0);

  const handleClick = () => {
    setCount(count + 1);
  };

  return (
    <div className="min-h-screen flex items-center justify-center p-4">
      <Card className="w-full max-w-md">
        <CardHeader>
          <CardTitle>Welcome to Your OverSkill App</CardTitle>
          <CardDescription>
            This is your starting template with all the essentials configured.
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="text-center">
            <p className="text-2xl font-bold mb-4">Count: {count}</p>
            <Button onClick={handleClick} size="lg">
              Increment
            </Button>
          </div>
          <div className="text-sm text-muted-foreground space-y-2">
            <p>✅ React 18 with TypeScript</p>
            <p>✅ Tailwind CSS & shadcn/ui components</p>
            <p>✅ Simplified deployment-ready setup</p>
            <p>✅ Clean architecture</p>
            <p>✅ Dark mode support</p>
            <p>✅ Cloudflare Workers ready</p>
          </div>
        </CardContent>
      </Card>
    </div>
  );
}
